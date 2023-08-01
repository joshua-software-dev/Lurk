const builtin = @import("builtin");
const std = @import("std");

const msgt = @import("message_types.zig");
const state = @import("discord_state.zig");

const iguanaTLS = @import("iguanaTLS");
const uuid = @import("uuid");
const ws = @import("ws");


const CLIENT_ID = "207646673902501888";
const EXPECTED_API_VERSION = 1;
const HOST = "127.0.0.1";
const HTTP_API_URL = "https://streamkit.discord.com/overlay/token";
const JSON_BUFFER_SIZE = 1024;
const PORT = 6463;
const PORT_RANGE = slice_from_int_range(u16, PORT, PORT + 10);
const QUERY = "/?v=1&client_id=";
const SCHEME = "ws://";
const WS_READ_BUFFER_SIZE = 1024 * 64;
const WS_WRITE_BUFFER_SIZE = 1024 * 4;

const HTTP_API_URI =
    std.Uri.parse(HTTP_API_URL)
    catch @panic("Failed to parse HTTP API URL");
const WS_API_URI =
    std.Uri.parse(std.fmt.comptimePrint("{s}{s}:{d}{s}{s}", .{ SCHEME, HOST, PORT, QUERY, CLIENT_ID }))
    catch @panic("Failed to parse WS API URL");
const ws_logger = std.log.scoped(.WS);

var access_token = std.BoundedArray(u8, 32).init(0) catch @panic("Failed to init access_token");
var ws_read_buffer: [1024*64]u8 = undefined;

inline fn slice_from_int_range(comptime T: type, comptime start: comptime_int, comptime end: comptime_int) []const T
{
    const length = end - start;
    var buffer: [length]T = undefined;

    for (start..end, 0..) |it, index|
    {
        buffer[index] = it;
    }
    return &buffer;
}

pub const DiscordWsConn = struct
{
    const Self = @This();
    conn: ws.Connection(WS_READ_BUFFER_SIZE, WS_WRITE_BUFFER_SIZE),
    fba: std.heap.FixedBufferAllocator,
    long_lived_allocator: std.mem.Allocator,
    buffer: [2 * 1024 * 1024]u8, // 2 MiB
    state: state.DiscordState,

    pub fn init(self: *Self, allocator: std.mem.Allocator) !std.Uri
    {
        self.long_lived_allocator = allocator;

        self.state = undefined;
        try self.state.init(self.long_lived_allocator);

        self.fba = std.heap.FixedBufferAllocator.init(&self.buffer);

        var localUri = WS_API_URI;
        for (PORT_RANGE) |current_port|
        {
            localUri.port.? = current_port;
            self.conn = ws.connectWithSpecifiedBufferSizes
            (
                self.long_lived_allocator,
                localUri,
                &.{
                    .{"Host", std.fmt.comptimePrint("{s}:{d}", .{ HOST, PORT })},
                    .{"Origin", "https://streamkit.discord.com"}
                },
                WS_READ_BUFFER_SIZE,
                WS_WRITE_BUFFER_SIZE,
            )
            catch |err|
            {
                if (err == error.ConnectionRefused and current_port < PORT_RANGE[PORT_RANGE.len - 1]) continue;
                return err;
            };

            self.conn.ws_client.receiver.buffer = ws_read_buffer;
            break;
        }

        return localUri;
    }

    pub fn close(self: *Self) void
    {
        defer self.fba.reset();
        defer self.state.deinit();
        defer self.conn.close() catch {};
        defer self.conn.deinit(self.long_lived_allocator);
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
                    .access_token = access_token.constSlice()
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

    // Someday, I'll flick a switch and this will just work, but for now some
    // memory leak when reading system certs taints the General Purpose
    // Allocator somehow, and completely corrupts the memory in the ws client
    pub fn authorize_stage_2_native(self: *Self, auth_code: []const u8) !void
    {
        var localBuf: [1024*1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&localBuf);
        var allocator = fba.allocator();

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var headers = std.http.Headers { .allocator = allocator };
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
        try std.json.stringify
        (
            .{ .code = auth_code },
            .{},
            req.writer()
        );
        try req.finish();
        try req.wait();

        if (req.response.status != .ok)
        {
            return error.AuthFailed;
        }

        var reqJsonReader = std.json.reader(allocator, req.reader());
        defer reqJsonReader.deinit();

        const tokenHolder = try std.json.parseFromTokenSource
        (
            msgt.AccessTokenHolder,
            allocator,
            &reqJsonReader,
            .{}
        );
        defer tokenHolder.deinit();

        try access_token.resize(tokenHolder.value.access_token.len);
        try access_token.replaceRange(0, tokenHolder.value.access_token.len, tokenHolder.value.access_token);

        fba.reset();

        try self.authenticate();
    }

    // Temporary solution, hopefully to be replaced with the native zig
    // function above. More likely, in the short term it will be replaced by
    // libcurl bindings...
    pub fn authorize_stage_2_subprocess(self: *Self, auth_code: []const u8) !void
    {
        var buf: [JSON_BUFFER_SIZE]u8 = undefined;
        const jsonBody = try std.fmt.bufPrint(&buf, "{{\"code\":\"{s}\"}}", .{auth_code});

        const result = try std.ChildProcess.exec
        (
            .{
                .allocator = self.fba.allocator(),
                .argv =
                &.{
                    "curl",
                    "-X",
                    "POST",
                    HTTP_API_URL,
                    "-H",
                    "Content-Type: application/json",
                    "-d",
                    jsonBody
                },
                .cwd = null,
                .env_map = null,
                .max_output_bytes = JSON_BUFFER_SIZE
            }
        );
        defer
        {
            const allocator = self.fba.allocator();
            allocator.free(result.stderr);
            allocator.free(result.stdout);
        }

        switch (result.term)
        {
            .Exited => |code| if (code != 0) return error.CommandFailed,
            else => return error.CommandFailed,
        }

        const tokenHolder = try std.json.parseFromSlice
        (
            msgt.AccessTokenHolder,
            self.fba.allocator(),
            result.stdout,
            .{}
        );
        defer tokenHolder.deinit();

        try access_token.resize(tokenHolder.value.access_token.len);
        try access_token.replaceRange(0, tokenHolder.value.access_token.len, tokenHolder.value.access_token);
        try self.authenticate();
    }

    // A less jank, but still jank solution to the std.http client not working
    // correctly. Its a damn good thing my use case is so simple that I only
    // need such a small subset of an http client.
    pub fn authorize_stage_2(self: *Self, auth_code: []const u8) !void
    {
        var responseBodyBuffer = try std.BoundedArray(u8, JSON_BUFFER_SIZE).init(0);

        {
            const sock = try std.net.tcpConnectToHost(self.fba.allocator(), "streamkit.discord.com", 443);
            defer sock.close();

            var client = try iguanaTLS.client_connect
            (
                .{
                    .reader = sock.reader(),
                    .writer = sock.writer(),
                    .cert_verifier = .none,
                    .temp_allocator = self.fba.allocator(),
                    .ciphersuites = iguanaTLS.ciphersuites.all,
                    .protocols = &[_][]const u8{"http/1.1"},
                    .rand = std.crypto.random
                },
                "streamkit.discord.com"
            );
            defer client.close_notify() catch {};

            {
                var jsonBuf: [JSON_BUFFER_SIZE]u8 = undefined;
                var jsonWriteStream = std.io.fixedBufferStream(&jsonBuf);

                try std.json.stringify
                (
                    .{ .code = auth_code },
                    .{},
                    jsonWriteStream.writer()
                );
                const jsonBody = jsonWriteStream.getWritten();

                try client.writer().print
                (
                    "POST {s} HTTP/1.1\r\n" ++
                    "Host: {s}\r\n" ++
                    "Accept: */*\r\n" ++
                    "Content-Type: application/json\r\n" ++
                    "Content-Length: {d}\r\n\r\n" ++
                    "{s}",
                    .{
                        HTTP_API_URI.path,
                        HTTP_API_URI.host.?,
                        jsonBody.len,
                        jsonBody
                    }
                );
            }

            {
                var headerRespBuf: [JSON_BUFFER_SIZE]u8 = undefined;
                var stream = std.io.fixedBufferStream(&headerRespBuf);
                const writer = stream.writer();

                try client.reader().streamUntilDelimiter(writer, '\n', stream.buffer.len);
                const header = stream.getWritten();
                try std.testing.expectEqualStrings("HTTP/1.1 200 OK", std.mem.trim(u8, header, &std.ascii.whitespace));
            }

            // Skip the rest of the headers except for Content-Length
            var content_length: ?usize = null;
            while (true)
            {
                var headerReadBuf: [JSON_BUFFER_SIZE]u8 = undefined;
                var stream = std.io.fixedBufferStream(&headerReadBuf);
                const writer = stream.writer();

                try client.reader().streamUntilDelimiter(writer, '\n', stream.buffer.len);
                const header = stream.getWritten();

                const hdr_contents = std.mem.trim(u8, header, &std.ascii.whitespace);
                if (hdr_contents.len == 0) break;

                if (std.mem.startsWith(u8, hdr_contents, "Content-Length: "))
                {
                    content_length = try std.fmt.parseUnsigned(usize, hdr_contents[16..], 10);
                }
            }

            try std.testing.expect(content_length != null);

            _ = try client.reader().readAtLeast(&responseBodyBuffer.buffer, content_length.?);
            try responseBodyBuffer.resize(content_length.?);
        }

        const tokenHolder = try std.json.parseFromSlice
        (
            msgt.AccessTokenHolder,
            self.fba.allocator(),
            responseBodyBuffer.constSlice(),
            .{}
        );
        defer tokenHolder.deinit();

        try access_token.resize(tokenHolder.value.access_token.len);
        try access_token.replaceRange(0, tokenHolder.value.access_token.len, tokenHolder.value.access_token);
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

    pub fn set_channel(self: *Self, new_channel: ?state.DiscordChannel) !void
    {
        if
        (
            new_channel == null or
            (
                new_channel != null and
                self.state.current_channel.*.channel_id.len > 0 and
                (
                    std.mem.eql
                    (
                        u8,
                        self.state.current_channel.*.channel_id.slice(),
                        new_channel.?.channel_id.slice()
                    )
                    and
                    std.mem.eql
                    (
                        u8,
                        self.state.current_channel.*.guild_id.slice(),
                        new_channel.?.guild_id.slice()
                    )
                )
            )
        )
        {
            return;
        }

        if (self.state.current_channel.*.channel_id.len > 0)
        {
            try self.unsubscribe(.VOICE_STATE_CREATE, self.state.current_channel.*);
            try self.unsubscribe(.VOICE_STATE_UPDATE, self.state.current_channel.*);
            try self.unsubscribe(.VOICE_STATE_DELETE, self.state.current_channel.*);
            try self.unsubscribe(.SPEAKING_START, self.state.current_channel.*);
            try self.unsubscribe(.SPEAKING_STOP, self.state.current_channel.*);
        }

        if (new_channel != null)
        {
            try self.subscribe(.VOICE_STATE_CREATE, new_channel);
            try self.subscribe(.VOICE_STATE_UPDATE, new_channel);
            try self.subscribe(.VOICE_STATE_DELETE, new_channel);
            try self.subscribe(.SPEAKING_START, new_channel);
            try self.subscribe(.SPEAKING_STOP, new_channel);
        }

        try self
            .state
            .current_channel
            .channel_id
            .resize(new_channel.?.channel_id.len);
        try self
            .state
            .current_channel
            .channel_id
            .replaceRange(0, new_channel.?.channel_id.len, new_channel.?.channel_id.slice());

        try self
            .state
            .current_channel
            .guild_id
            .resize(new_channel.?.guild_id.len);
        try self
            .state
            .current_channel
            .guild_id
            .replaceRange(0, new_channel.?.guild_id.len, new_channel.?.guild_id.slice());
    }

    pub fn parse_channel_info(self: *Self, msg: []const u8) !?state.DiscordChannel
    {
        const channelMsg = std.json.parseFromSlice
        (
            msgt.VoiceChannelSelectChannelData,
            self.fba.allocator(),
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
            self.fba.allocator(),
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
        var stream = std.io.fixedBufferStream(msg);

        var json_reader = std.json.reader(self.fba.allocator(), stream.reader());
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
        defer self.fba.reset();

        ws_logger.debug("raw message: {s}", .{ msg });
        var localMsg: msgt.Message = undefined;
        {
            const basicMsg = try std.json.parseFromSlice
            (
                msgt.Message,
                self.fba.allocator(),
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
                                self.fba.allocator(),
                                msg,
                                .{ .ignore_unknown_fields = true },
                            );
                            defer dataMsg.deinit();

                            if (dataMsg.value.data.v != EXPECTED_API_VERSION)
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
                        try self.set_channel(new_channel);
                    },
                    .VOICE_STATE_CREATE, .VOICE_STATE_UPDATE =>
                    {
                        var new_user: *state.DiscordUser = undefined;

                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.VoiceUpdateUserInfoAndVoiceStateData,
                                self.fba.allocator(),
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
                                self.fba.allocator(),
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
                                self.fba.allocator(),
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
                                self.fba.allocator(),
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
                        try access_token.resize(0);
                        self.state.free_user_hashmap();
                        try self.authorize_stage_1();
                    },
                    else =>
                    {
                        {
                            const dataMsg = try std.json.parseFromSlice
                            (
                                msgt.AuthSuccessData,
                                self.fba.allocator(),
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
                        self.fba.allocator(),
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
                try self.set_channel(new_channel);

                self.state.free_user_hashmap();
                {
                    const dataMsg = try std.json.parseFromSlice
                    (
                        msgt.VoiceStateData,
                        self.fba.allocator(),
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

    pub fn recieve_next_msg(self: *Self) !bool
    {
        ws_logger.debug("fixed buffer bytes in use: {d}", .{ self.fba.end_index });
        defer ws_logger.debug("fixed buffer bytes remaining: {d}\n", .{ self.fba.end_index });

        const msg = try self.conn.receive();
        switch (msg.type)
        {
            .text =>
            {
                ws_logger.debug("attempting to handle message...", .{});
                return try self.handle_message(msg.data);
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
                ws_logger.debug("got {s}: {s}", .{ @tagName(msg.type), msg.data });
                return true;
            },
        }
    }
};

test "a" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var allocator = arena.allocator();
    const auth_code = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    _ = auth_code;

    {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        // var headers = std.http.Headers { .allocator = allocator };
        // // try headers.append("Transfer-Encoding", "chunked");
        // // try headers.append("Content-Type", "application/json");
        // defer headers.deinit();

        var req: std.http.Client.Request = try client.request
        (
            .POST,
            HTTP_API_URI,
            .{ .allocator = allocator },
            std.http.Client.Options { .max_redirects = 10 }
        );
        req.transfer_encoding = .chunked;
        defer req.deinit();

        try req.start();
        // try std.json.stringify
        // (
        //     .{ .code = auth_code },
        //     .{},
        //     req.writer()
        // );
        try req.writer().writeAll(
            \\{"code":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
        );
        try req.finish();
        try req.wait();

        const body = try req.reader().readAllAlloc(allocator, 65535);
        defer allocator.free(body);

        // if (req.response.status != .ok)
        // {
        //     return error.AuthFailed;
        // }

        // var reqJsonReader = std.json.reader(arena.allocator(), req.reader());
        // defer reqJsonReader.deinit();

        // const accessTokenHolder = try std.json.parseFromTokenSource
        // (
        //     msgt.AccessTokenHolder,
        //     arena.allocator(),
        //     &reqJsonReader,
        //     .{}
        // );
        // defer accessTokenHolder.deinit();

        // std.debug.print("\n{s}\n", .{ accessTokenHolder.value.access_token });
    }

    // _ = arena.reset(.free_all);
    std.debug.print("{d}", .{ arena.queryCapacity() });
}

test "b" {
    const auth_code = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    var localBuf: [1024*1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&localBuf);
    var allocator = fba.allocator();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var headers = std.http.Headers { .allocator = allocator };
    defer headers.deinit();
    // try headers.append("Transfer-Encoding", "chunked");
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
    try std.json.stringify
    (
        .{ .code = auth_code },
        .{},
        req.writer()
    );
    try req.finish();
    try req.wait();

    if (req.response.status != .ok)
    {
        return error.AuthFailed;
    }

    var reqJsonReader = std.json.reader(allocator, req.reader());
    defer reqJsonReader.deinit();

    // const tokenHolder = try std.json.parseFromTokenSource
    // (
    //     msgt.AccessTokenHolder,
    //     allocator,
    //     &reqJsonReader,
    //     .{}
    // );
    // defer tokenHolder.deinit();

    // try access_token.resize(tokenHolder.value.access_token.len);
    // try access_token.replaceRange(0, tokenHolder.value.access_token.len, tokenHolder.value.access_token);

    fba.reset();
}
