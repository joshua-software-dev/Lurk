const builtin = @import("builtin");
const std = @import("std");

const certs = @import("preload_ssl_certs.zig");
const msgt = @import("message_types.zig");
const state = @import("discord_state.zig");

const uuid = @import("uuid");
const ws = @import("ws");


const CLIENT_ID = "207646673902501888";
const EXPECTED_API_VERSION = 1;
const HOST = "127.0.0.1";
const HTTP_API_URL = "https://streamkit.discord.com/overlay/token";
const JSON_BUFFER_SIZE = 1024;
const MSG_BUFFER_START_SIZE = 1024 * 64;
const PORT_RANGE: []const u16 = &[_]u16{ 6463, 6464, 6465, 6466, 6467, 6468, 6469, 6470, 6471, 6472, };

const HTTP_API_URI =
    std.Uri.parse(HTTP_API_URL)
    catch @panic("Failed to parse HTTP API URL");
const WS_API_URI =
    std.Uri.parse(std.fmt.comptimePrint("ws://{s}:{d}/?v=1&client_id={s}", .{ HOST, PORT_RANGE[0], CLIENT_ID }))
    catch @panic("Failed to parse WS API URL");
const ws_logger = std.log.scoped(.WS);

pub const DiscordWsConn = struct
{
    const Self = @This();
    access_token: std.BoundedArray(u8, 32),
    allocator: std.mem.Allocator,
    connection_closed: bool = false,
    connection_uri: std.Uri,
    msg_buffer: msgt.MessageBackingBuffer,
    cert_bundle: std.crypto.Certificate.Bundle,
    conn: ws.UnbufferedConnection,
    state: state.DiscordState,

    pub fn init
    (
        allocator: std.mem.Allocator,
        bundle: ?std.crypto.Certificate.Bundle,
    )
    !DiscordWsConn
    {
        var buf = try std.ArrayList(u8).initCapacity(allocator, MSG_BUFFER_START_SIZE);
        var final_uri = WS_API_URI;

        return .{
            .access_token = try std.BoundedArray(u8, 32).init(0),
            .allocator = allocator,
            .cert_bundle = if (bundle) |*bund| @constCast(bund).* else try certs.preload_ssl_certs(allocator),
            .connection_uri = final_uri,
            .msg_buffer = .{ .dynamic = buf },
            .conn = try connect(&final_uri),
            .state = try state.DiscordState.init(allocator),
        };
    }

    pub fn initMinimalAlloc
    (
        allocator: std.mem.Allocator,
        bundle: ?std.crypto.Certificate.Bundle,
    )
    !DiscordWsConn
    {
        var buf = try std.ArrayListUnmanaged(u8).initCapacity(allocator, MSG_BUFFER_START_SIZE);
        var final_uri = WS_API_URI;

        return .{
            .access_token = try std.BoundedArray(u8, 32).init(0),
            .allocator = allocator,
            .cert_bundle = if (bundle) |*bund| @constCast(bund).* else try certs.preload_ssl_certs(allocator),
            .connection_uri = final_uri,
            .msg_buffer = .{ .fixed = buf },
            .conn = try connect(&final_uri),
            .state = try state.DiscordState.init(allocator),
        };
    }

    pub fn connect(final_uri: *std.Uri) !ws.UnbufferedConnection
    {
        for (PORT_RANGE) |current_port|
        {
            final_uri.port.? = current_port;
            var buf: [256]u8 = undefined;
            var conn = ws.connect_unbuffered
            (
                null,
                final_uri.*,
                &.{
                    .{ "Host", try std.fmt.bufPrint(&buf, "{s}:{d}", .{ HOST, current_port, }) },
                    .{ "Origin", "https://streamkit.discord.com" }
                },
            )
            catch |err|
            {
                if (err == error.ConnectionRefused)
                {
                    std.log.scoped(.WS).warn("Connection Failed: {+/}", .{ final_uri.* });
                }

                if (err == error.ConnectionRefused and current_port < PORT_RANGE[PORT_RANGE.len - 2]) continue;
                return err;
            };

            return conn;
        }

        unreachable;
    }

    pub fn close(self: *Self) void
    {
        if (!self.connection_closed)
        {
            self.connection_closed = true;
            defer self.cert_bundle.deinit(self.allocator);
            defer
            {
                switch (self.msg_buffer)
                {
                    .dynamic => |*d| d.deinit(),
                    .fixed => |*f| f.deinit(self.allocator),
                }
            }
            defer self.conn.deinit();
            defer self.state.deinit();
        }
    }

    pub fn send_ws_message(self: *Self, object: anytype, options: std.json.StringifyOptions) !void
    {
        var buf: [JSON_BUFFER_SIZE]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();

        try std.json.stringify(object, options, writer);

        const msg = stream.getWritten();
        try self.conn.send(.text, msg);
        ws_logger.debug("sent: {s}", .{msg});
    }

    pub fn authenticate(self: *Self) !void
    {
        try self.send_ws_message
        (
            .{
                .cmd = @tagName(msgt.Command.AUTHENTICATE),
                .args =
                .{
                    .access_token = self.access_token.constSlice()
                },
                .nonce = uuid.urn.serialize(uuid.v4.new())
            },
            .{ .emit_null_optional_fields = true }
        );
    }

    pub fn authorize_stage_1(self: *Self) !void
    {
        try self.send_ws_message
        (
            .{
                .cmd = @tagName(msgt.Command.AUTHORIZE),
                .args =
                .{
                    .client_id = CLIENT_ID,
                    .scopes = [_][]const u8 { "rpc", "messages.read", "rpc.notifications.read" },
                    .prompt = "none"
                },
                .nonce = uuid.urn.serialize(uuid.v4.new())
            },
            .{}
        );
    }

    pub fn authorize_stage_2(self: *Self, auth_code: []const u8) !void
    {
        {
            var auth_buf: [64]u8 = undefined;
            var auth_stream = std.io.fixedBufferStream(&auth_buf);
            try std.json.stringify(.{ .code = auth_code, }, .{}, auth_stream.writer());

            // deinit unnecessary due to client.deinit calling it
            var temp_bundle = std.crypto.Certificate.Bundle
            {
                .bytes = try self.cert_bundle.bytes.clone(self.allocator),
            };

            {
                const now_sec = std.time.timestamp();
                var iter = self.cert_bundle.map.iterator();
                while (iter.next()) |it|
                {
                    try temp_bundle.parseCert(self.allocator, it.value_ptr.*, now_sec);
                }
            }

            var client = std.http.Client
            {
                .allocator = self.allocator,
                .ca_bundle = temp_bundle,
                .next_https_rescan_certs = false,
            };
            defer client.deinit();

            var headers = std.http.Headers{ .allocator = self.allocator, };
            defer headers.deinit();
            try headers.append("Content-Type", "application/json");

            var req = try client.request
            (
                .POST,
                HTTP_API_URI,
                headers,
                std.http.Client.Options { .max_redirects = 10 }
            );
            req.transfer_encoding = .chunked;
            defer req.deinit();

            try req.start();
            try req.writeAll(auth_stream.getWritten());
            try req.finish();
            try req.wait();

            if (req.response.status != .ok)
            {
                return error.AuthFailed;
            }

            var req_json_reader = std.json.reader(self.allocator, req.reader());
            defer req_json_reader.deinit();

            const tokenHolder = try std.json.parseFromTokenSource
            (
                msgt.AccessTokenHolder,
                self.allocator,
                &req_json_reader,
                .{}
            );
            defer tokenHolder.deinit();

            self.access_token.len = 0;
            try self.access_token.appendSlice(tokenHolder.value.access_token);
        }

        try self.authenticate();
    }

    pub fn subscribe(self: *Self, event: msgt.Event, channel: ?state.DiscordChannel) !void
    {
        if (channel == null)
        {
            try self.send_ws_message
            (
                .{
                    .args = @as(struct {}, .{}),
                    .cmd = @tagName(msgt.Command.SUBSCRIBE),
                    .evt = @tagName(event),
                    .nonce = &uuid.urn.serialize(uuid.v4.new())
                },
                .{ .emit_null_optional_fields = true }
            );
        }
        else
        {
            try self.send_ws_message
            (
                .{
                    .args = .{ .channel_id = channel.?.channel_id.constSlice() },
                    .cmd = @tagName(msgt.Command.SUBSCRIBE),
                    .evt = @tagName(event),
                    .nonce = &uuid.urn.serialize(uuid.v4.new())
                },
                .{ .emit_null_optional_fields = true }
            );
        }
    }

    pub fn unsubscribe(self: *Self, event: msgt.Event, channel: ?state.DiscordChannel) !void
    {
        if (channel == null)
        {
            try self.send_ws_message
            (
                .{
                    .args = @as(struct {}, .{}),
                    .cmd = @tagName(msgt.Command.UNSUBSCRIBE),
                    .evt = @tagName(event),
                    .nonce = &uuid.urn.serialize(uuid.v4.new())
                },
                .{ .emit_null_optional_fields = true },
            );
        }
        else
        {
            try self.send_ws_message
            (
                .{
                    .args = .{ .channel_id = channel.?.channel_id.constSlice() },
                    .cmd = @tagName(msgt.Command.UNSUBSCRIBE),
                    .evt = @tagName(event),
                    .nonce = &uuid.urn.serialize(uuid.v4.new())
                },
                .{ .emit_null_optional_fields = true },
            );
        }
    }

    pub fn send_get_selected_voice_channel(self: *Self) !void
    {
        try self.send_ws_message
        (
            .{
                .cmd = @tagName(msgt.Command.GET_SELECTED_VOICE_CHANNEL),
                .nonce = uuid.urn.serialize(uuid.v4.new())
            },
            .{ .emit_null_optional_fields = true },
        );
    }

    pub fn parse_channel_info(self: *Self, msg: []const u8) !?state.DiscordChannel
    {
        _ = self;
        var buf: [JSON_BUFFER_SIZE]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);

        const channelMsg = std.json.parseFromSlice
        (
            msgt.VoiceChannelSelectChannelData,
            fba.allocator(),
            msg,
            .{ .ignore_unknown_fields = true },
        )
        catch
        {
            return null;
        };
        defer channelMsg.deinit();

        const guildMsg = std.json.parseFromSlice
        (
            msgt.VoiceChannelSelectGuildData,
            fba.allocator(),
            msg,
            .{ .ignore_unknown_fields = true },
        )
        catch
        {
            return null;
        };
        defer guildMsg.deinit();

        if
        (
            channelMsg.value.data != null and
            guildMsg.value.data != null and
            channelMsg.value.data.?.channel_id != null and
            guildMsg.value.data.?.guild_id != null
        )
        {

            return state.DiscordChannel
            {
                .channel_id = try state.ChannelId.fromSlice(channelMsg.value.data.?.channel_id.?),
                .guild_id = try state.GuildId.fromSlice(guildMsg.value.data.?.guild_id.?),
            };
        }

        return null;
    }

    pub fn parse_get_selected_voice_channel_dynamic(self: *Self, msg: []const u8) !?state.DiscordChannel
    {
        _ = self;
        var buf: [JSON_BUFFER_SIZE]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);

        var stream = std.io.fixedBufferStream(msg);

        var json_reader = std.json.reader(fba.allocator(), stream.reader());
        defer json_reader.deinit();

        var channel_id: ?[]const u8 = null;
        var guild_id: ?[]const u8 = null;

        while (true)
        {
            const token = try json_reader.next();
            if (token == .end_of_document) break;

            if (json_reader.scanner.string_is_object_key)
            {
                if (std.mem.eql(u8, "messages", token.string))
                {
                    break;
                }
                else if
                (
                    std.mem.eql(u8, "id", token.string) and
                    json_reader.stackHeight() == 2
                )
                {
                    var next_token = try json_reader.next();
                    channel_id = next_token.string;
                }
                else if
                (
                    std.mem.eql(u8, "guild_id", token.string) and
                    json_reader.stackHeight() == 2
                )
                {
                    var next_token = try json_reader.next();
                    guild_id = next_token.string;
                }
            }

            if (channel_id != null and guild_id != null)
            {
                break;
            }
        }

        if (channel_id != null and guild_id != null)
        {
            ws_logger.debug("dynamic | channel_id: {s} guild_id: {s}", .{ channel_id.?, guild_id.? });
            return state.DiscordChannel
            {
                .channel_id = try state.ChannelId.fromSlice(channel_id.?),
                .guild_id = try state.GuildId.fromSlice(guild_id.?),
            };
        }

        return null;
    }

    pub fn handle_message(self: *Self, msg: []const u8) !bool
    {
        var buf: [JSON_BUFFER_SIZE]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);

        ws_logger.debug("raw message: {s}", .{ msg });
        var localMsg: msgt.Message = undefined;
        {
            const basicMsg = try std.json.parseFromSlice
            (
                msgt.Message,
                fba.allocator(),
                msg,
                .{ .ignore_unknown_fields = true },
            );
            defer basicMsg.deinit();

            localMsg.cmd = basicMsg.value.cmd;
            localMsg.evt = basicMsg.value.evt;
            localMsg.nonce = basicMsg.value.nonce;
        }
        ws_logger.debug("parsed message: {}", .{ localMsg });

        switch (localMsg.cmd)
        {
            .DISPATCH =>
            {
                switch (localMsg.evt.?)
                {
                    .READY =>
                    {
                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.EventReadyData,
                                fba.allocator(),
                                msg,
                                .{ .ignore_unknown_fields = true },
                            );
                            defer dataMsg.deinit();

                            const versionFound: u32 = @intFromFloat(dataMsg.value.data.v);
                            if (versionFound != EXPECTED_API_VERSION)
                            {
                                ws_logger.err
                                (
                                    "Unexpected API Version: {d}, expected {d}",
                                    .{ dataMsg.value.data.v, EXPECTED_API_VERSION }
                                );
                                return false;
                            }
                        }

                        try self.authenticate();
                    },
                    .VOICE_CHANNEL_SELECT =>
                    {
                        const new_channel = try self.parse_channel_info(msg);
                        if (new_channel == null)
                        {
                            self.state.free_user_hashmap();
                        }
                        try self.state.set_channel(self, new_channel);
                    },
                    .VOICE_STATE_CREATE, .VOICE_STATE_UPDATE =>
                    {
                        var new_user: *state.DiscordUser = undefined;

                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.VoiceUpdateUserInfoAndVoiceStateData,
                                fba.allocator(),
                                msg,
                                .{ .ignore_unknown_fields = true },
                            );
                            defer dataMsg.deinit();

                            if (dataMsg.value.data) |data|
                            {
                                ws_logger.debug("update: {s} {s}", .{ data.nick, data.user.id });
                                new_user = try self.state.parse_or_update_one_voice_state(dataMsg.value.data.?);
                            }
                            else
                            {
                                return false;
                            }
                        }

                        if
                        (
                            localMsg.evt.? == .VOICE_STATE_CREATE and
                            self.state.self_user_id.len > 0 and
                            std.mem.eql(u8, self.state.self_user_id.slice(), new_user.user_id.slice())
                        )
                        {
                            try self.send_get_selected_voice_channel();
                        }
                    },
                    .VOICE_STATE_DELETE =>
                    {
                        var clear = false;
                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.AuthSuccessData,
                                fba.allocator(),
                                msg,
                                .{ .ignore_unknown_fields = true },
                            );
                            defer dataMsg.deinit();

                            _ = self.state.all_users.orderedRemove(dataMsg.value.data.user.id);
                            clear =
                                self.state.self_user_id.len > 0 and
                                std.mem.eql(u8, self.state.self_user_id.slice(), dataMsg.value.data.user.id);

                        }

                        if (clear)
                        {
                            self.state.free_user_hashmap();
                            try self.send_get_selected_voice_channel();
                        }
                    },
                    .SPEAKING_START =>
                    {
                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.VoiceSpeakingStartStopData,
                                fba.allocator(),
                                msg,
                                .{ .ignore_unknown_fields = true },
                            );
                            defer dataMsg.deinit();

                            var maybeUser = self.state.all_users.getPtr(dataMsg.value.data.user_id);
                            if (maybeUser) |user|
                            {
                                user.*.speaking = true;
                            }
                            else
                            {
                                ws_logger.warn("Could not find user with id: {d}", .{ dataMsg.value.data.user_id });
                            }
                        }
                    },
                    .SPEAKING_STOP =>
                    {
                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.VoiceSpeakingStartStopData,
                                fba.allocator(),
                                msg,
                                .{ .ignore_unknown_fields = true },
                            );
                            defer dataMsg.deinit();

                            var maybeUser = self.state.all_users.getPtr(dataMsg.value.data.user_id);
                            if (maybeUser) |user|
                            {
                                user.*.speaking = false;
                            }
                            else
                            {
                                ws_logger.warn("Could not find user with id: {d}", .{ dataMsg.value.data.user_id });
                            }
                        }
                    },
                    else => @panic("Unexpected Event")
                }
            },
            .AUTHENTICATE =>
            {
                switch (localMsg.evt orelse .READY)
                {
                    .ERROR =>
                    {
                        self.access_token.len = 0;
                        self.state.free_user_hashmap();
                        try self.authorize_stage_1();
                    },
                    else =>
                    {
                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.AuthSuccessData,
                                fba.allocator(),
                                msg,
                                .{ .ignore_unknown_fields = true },
                            );
                            defer dataMsg.deinit();

                            try self.state.self_user_id.resize(dataMsg.value.data.user.id.len);
                            try self.state.self_user_id.replaceRange
                            (
                                0,
                                dataMsg.value.data.user.id.len,
                                dataMsg.value.data.user.id
                            );
                        }

                        try self.subscribe(.VOICE_CHANNEL_SELECT, null);
                        try self.send_get_selected_voice_channel();
                    }
                }

            },
            .AUTHORIZE =>
            {
                var localDataMsg: msgt.AuthCodeData = undefined;

                {
                    const dataMsg = try std.json.parseFromSlice
                    (
                        msgt.AuthCodeData,
                        fba.allocator(),
                        msg,
                        .{ .ignore_unknown_fields = true },
                    );
                    defer dataMsg.deinit();

                    localDataMsg.data.code = dataMsg.value.data.code;
                }

                ws_logger.debug("Attempting stage 2 auth...", .{});
                try self.authorize_stage_2(localDataMsg.data.code);
            },
            .GET_SELECTED_VOICE_CHANNEL =>
            {
                const new_channel = try self.parse_get_selected_voice_channel_dynamic(msg);
                try self.state.set_channel(self, new_channel);

                self.state.free_user_hashmap();
                {
                    const dataMsg = try std.json.parseFromSlice
                    (
                        msgt.VoiceStateData,
                        fba.allocator(),
                        msg,
                        .{ .ignore_unknown_fields = true },
                    );
                    defer dataMsg.deinit();

                    try self.state.parse_voice_state_data(dataMsg.value);
                }
            },
            .SUBSCRIBE => { },
            .UNSUBSCRIBE => { },
            else => @panic("Unexpected Command")
        }

        return true;
    }

    pub fn recieve_next_msg(self: *Self, timeout_ns: u64) !bool
    {
        var msg = switch (self.msg_buffer)
        {
            .dynamic => |*d|
            blk: {
                d.clearRetainingCapacity();
                break :blk try self.conn.receiveIntoWriter(d.writer(), 0, timeout_ns);
            },
            .fixed => |*f|
            blk: {
                f.clearRetainingCapacity();
                break :blk try self.conn.receiveIntoBuffer(f.allocatedSlice(), timeout_ns);
            },
        };

        switch (msg.type)
        {
            .text =>
            {
                ws_logger.debug("attempting to handle message...", .{});
                switch (msg.data)
                {
                    .slice => |slice|
                    {
                        ws_logger.debug("msg is slice", .{});
                        return try self.handle_message(slice);
                    },
                    .written => |write_length|
                    {
                        ws_logger.debug("msg is writer", .{});
                        return try self.handle_message(self.msg_buffer.dynamic.items[0..@truncate(write_length)]);
                    },
                    else => return error.UnexpectedMessageDataType,
                }
            },
            .ping =>
            {
                ws_logger.debug("got ping! sending pong...", .{});
                try self.conn.pong();
                return true;
            },
            .close =>
            {
                ws_logger.debug("close", .{});
                return false;
            },
            else =>
            {
                ws_logger.debug("got {s}: {any}", .{ @tagName(msg.type), msg.data });
                return true;
            },
        }
    }
};
