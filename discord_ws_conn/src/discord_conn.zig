const builtin = @import("builtin");
const std = @import("std");

const certs = @import("preload_ssl_certs.zig");
const httpmode = @import("http_mode.zig");
const msgt = @import("message_types.zig");
const state = @import("discord_state.zig");

const iguana = @import("iguanaTLS");
const uuid = @import("uuid");
const ws = @import("ws");
const UnbufferedMessage = @typeInfo
(
    @typeInfo
    (
        @TypeOf(ws.UnbufferedConnection.receiveIntoBuffer)
    ).Fn.return_type.?
).ErrorUnion.payload;

fn start_0110(req: *std.http.Client.Request, args: anytype) !void
{
    _ = args;
    try req.start();
}

fn start_0120(req: *std.http.Client.Request, args: anytype) !void
{
    try req.start(args);
}

const start_func =
    if (builtin.zig_version.order(std.SemanticVersion.parse("0.11.0") catch unreachable) == .gt)
        start_0120
    else
        start_0110;

const AVATAR_API_URL = "https://cdn.discordapp.com/avatars/{s}/{s}.png"; // user_id, avatar_id
const AVATAR_MAX_SIZE = 1024 * 1024 * 8; // 8 Megabytes
const CLIENT_ID = "207646673902501888";
const EXPECTED_API_VERSION = 1;
const HOST = "127.0.0.1";
const HTTP_API_URL = "https://streamkit.discord.com/overlay/token";
const HTTP_BUFFER_SIZE_IGUANATLS = 1024 * 20;
const HTTP_BUFFER_SIZE_PROCESS = 1024 * 32;
const JSON_BUFFER_SIZE = 1024;
const MSG_BUFFER_SIZE = 1024 * 64;
const PORT_RANGE: []const u16 = &[_]u16{ 6463, 6464, 6465, 6466, 6467, 6468, 6469, 6470, 6471, 6472, };

const HTTP_API_URI =
    std.Uri.parse(HTTP_API_URL)
    catch unreachable;
const WS_API_URI =
    std.Uri.parse(std.fmt.comptimePrint("ws://{s}:{d}/?v=1&client_id={s}", .{ HOST, PORT_RANGE[0], CLIENT_ID }))
    catch unreachable;
const ws_logger = std.log.scoped(.WS);

pub const DiscordWsConn = struct
{
    const Self = @This();
    connection_closed: bool = false,
    connection_uri: std.Uri,
    access_token: std.BoundedArray(u8, 32),
    http_mode: httpmode.HttpMode,
    cert_bundle: ?std.crypto.Certificate.Bundle,
    msg_backing_allocator: std.mem.Allocator,
    msg_backing: *[MSG_BUFFER_SIZE]u8,
    msg_allocator: std.heap.FixedBufferAllocator,
    conn: ws.UnbufferedConnection,
    state: state.DiscordState,

    pub fn init
    (
        state_allocator: std.mem.Allocator,
        image_allocator: ?std.mem.Allocator,
        http_mode: httpmode.HttpMode,
    )
    !DiscordWsConn
    {
        var final_uri = WS_API_URI;

        var cert_bundle: ?std.crypto.Certificate.Bundle = null;
        var msg_backing_allocator: std.mem.Allocator = state_allocator;

        switch (http_mode)
        {
            .ChildProcess => |maybe_child|
            {
                if (maybe_child) |child|
                {
                    msg_backing_allocator = child;
                }
            },
            .IguanaTLS => |maybe_iguana|
            {
                if (maybe_iguana) |iguana_alloc|
                {
                    msg_backing_allocator = iguana_alloc;
                }
            },
            .StdLibraryHttp => |std_http|
            {
                if (std_http.message_allocator) |msg_alloc|
                {
                    msg_backing_allocator = msg_alloc;
                }

                switch (std_http.bundle)
                {
                    .allocate_new => |new_allocator|
                    {
                        cert_bundle = try certs.preload_ssl_certs
                        (
                            new_allocator,
                            std_http.final_cert_allocator,
                        );
                    },
                    .use_existing => |existing|
                    {
                        cert_bundle = existing;
                    },
                }
            },
        }

        const msg_backing: *[MSG_BUFFER_SIZE]u8 = try msg_backing_allocator.create([MSG_BUFFER_SIZE]u8);

        return .{
            .access_token = std.BoundedArray(u8, 32).init(0) catch unreachable,
            .cert_bundle = cert_bundle,
            .conn = try connect(&final_uri),
            .connection_uri = final_uri,
            .http_mode = http_mode,
            .msg_backing_allocator = msg_backing_allocator,
            .msg_backing = msg_backing,
            .msg_allocator = std.heap.FixedBufferAllocator.init(&msg_backing.*),
            .state = try state.DiscordState.init(state_allocator, image_allocator),
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

            if (self.cert_bundle != null) self.cert_bundle.?.deinit(self.http_mode.StdLibraryHttp.final_cert_allocator);
            self.msg_backing_allocator.free(self.msg_backing);

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

    pub fn authorize_stage_2_iguana(self: *Self, auth_code: []const u8) !void
    {
        {
            var fba_buf: [HTTP_BUFFER_SIZE_IGUANATLS]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
            var allocator = fba.allocator();
            const json_code = try std.json.stringifyAlloc(fba.allocator(), .{ .code = auth_code, }, .{});

            const out_buf = try allocator.create([512]u8);
            defer allocator.free(out_buf);
            var message_length: ?usize = null;

            {
                var net_stream: std.net.Stream = try std.net.tcpConnectToHost
                (
                    allocator,
                    HTTP_API_URI.host.?,
                    if (comptime std.mem.eql(u8, HTTP_API_URI.scheme, "https")) 443 else 80,
                );
                defer net_stream.close();

                var random = blk:
                {
                    var seed: [std.rand.DefaultCsprng.secret_seed_length]u8 = undefined;
                    try std.os.getrandom(&seed);
                    break :blk std.rand.DefaultCsprng.init(seed);
                };

                var tls_stream = try iguana.client_connect
                (
                    .{
                        .rand = random.random(),
                        .reader = net_stream.reader(),
                        .writer = net_stream.writer(),
                        .temp_allocator = allocator,
                        .cert_verifier = .none, // TODO: Enable this
                    },
                    HTTP_API_URI.host.?,
                );
                defer tls_stream.close_notify() catch {};

                {
                    const write_msg = try std.fmt.allocPrint
                    (
                        fba.allocator(),
                        "POST {/} HTTP/1.1\r\n" ++
                        "HOST: {s}\r\n" ++
                        "User-Agent: Lurk (iguanaTLS)\r\n" ++
                        "Accept: */*\r\n" ++
                        "Content-Type: application/json\r\n" ++
                        "Content-Length: {d}\r\n" ++
                        "\r\n" ++
                        "{s}\r\n" ++
                        "\r\n",
                        .{
                            HTTP_API_URI,
                            HTTP_API_URI.host.?,
                            json_code.len,
                            json_code,
                        },
                    );
                    defer allocator.free(write_msg);
                    _ = try tls_stream.write(write_msg);
                }

                while (true)
                {
                    var read_buf: [1]u8 = undefined;
                    if ((try tls_stream.read(&read_buf)) < 1) return error.EndOfStream;

                    switch (read_buf[0])
                    {
                        '\r' =>
                        {
                            var secondary_buf: [3]u8 = undefined;
                            if ((try tls_stream.read(&secondary_buf)) < 3) return error.EndOfStream;

                            if (std.mem.eql(u8, &secondary_buf, "\n\r\n")) break;
                        },
                        else => {}
                    }
                }

                message_length = try tls_stream.read(&out_buf.*);
            }

            const token_holder = try std.json.parseFromSlice
            (
                msgt.AccessTokenHolder,
                allocator,
                out_buf[0..message_length.?],
                .{},
            );
            defer token_holder.deinit();

            self.access_token.len = 0;
            try self.access_token.appendSlice(token_holder.value.access_token);
        }

        try self.authenticate();
    }

    pub fn authorize_stage_2_std(self: *Self, auth_code: []const u8) !void
    {
        {
            var auth_buf: [64]u8 = undefined;
            var auth_stream = std.io.fixedBufferStream(&auth_buf);
            try std.json.stringify(.{ .code = auth_code, }, .{}, auth_stream.writer());
            const json_code = auth_stream.getWritten();

            // deinit unnecessary due to client.deinit calling it
            var temp_bundle = std.crypto.Certificate.Bundle
            {
                .bytes = try self.cert_bundle.?.bytes.clone(self.http_mode.StdLibraryHttp.http_allocator),
            };

            {
                const now_sec = std.time.timestamp();
                var iter = self.cert_bundle.?.map.iterator();
                while (iter.next()) |it|
                {
                    try temp_bundle.parseCert(self.http_mode.StdLibraryHttp.http_allocator, it.value_ptr.*, now_sec);
                }
            }

            var client = std.http.Client
            {
                .allocator = self.http_mode.StdLibraryHttp.http_allocator,
                .ca_bundle = temp_bundle,
                .next_https_rescan_certs = false,
            };
            defer client.deinit();

            var headers = std.http.Headers{ .allocator = self.http_mode.StdLibraryHttp.http_allocator, };
            defer headers.deinit();
            try headers.append("Content-Type", "application/json");

            var req = try client.request
            (
                .POST,
                HTTP_API_URI,
                headers,
                .{ .max_redirects = 10 }
            );
            req.transfer_encoding = .chunked;
            defer req.deinit();

            try start_func(&req, .{});
            try req.writeAll(json_code);
            try req.finish();
            try req.wait();

            if (req.response.status != .ok)
            {
                return error.AuthFailed;
            }

            var req_json_reader = std.json.reader(self.http_mode.StdLibraryHttp.http_allocator, req.reader());
            defer req_json_reader.deinit();

            const token_holder = try std.json.parseFromTokenSource
            (
                msgt.AccessTokenHolder,
                self.http_mode.StdLibraryHttp.http_allocator,
                &req_json_reader,
                .{}
            );
            defer token_holder.deinit();

            self.access_token.len = 0;
            try self.access_token.appendSlice(token_holder.value.access_token);
        }

        try self.authenticate();
    }

    pub fn authorize_stage_2_process(self: *Self, auth_code: []const u8) !void
    {
        {
            var fba_buf: [HTTP_BUFFER_SIZE_PROCESS]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
            var allocator = fba.allocator();
            const json_code = try std.json.stringifyAlloc(allocator, .{ .code = auth_code, }, .{});

            const result = try std.ChildProcess.exec
            (
                .{
                    .allocator = allocator,
                    .argv =
                    &.{
                        "curl",
                        "-X",
                        "POST",
                        HTTP_API_URL,
                        "-H",
                        "Content-Type: application/json",
                        "-d",
                        json_code,
                    },
                    .cwd = null,
                    .env_map = null,
                    .max_output_bytes = JSON_BUFFER_SIZE
                }
            );

            switch (result.term)
            {
                .Exited => |code| if (code != 0) return error.CommandFailed,
                else => return error.CommandFailed,
            }

            const token_holder = try std.json.parseFromSlice
            (
                msgt.AccessTokenHolder,
                allocator,
                result.stdout,
                .{}
            );
            defer token_holder.deinit();

            self.access_token.len = 0;
            try self.access_token.appendSlice(token_holder.value.access_token);
        }

        try self.authenticate();
    }

    pub fn authorize_stage_2(self: *Self, auth_code: []const u8) !void
    {
        std.log.scoped(.WS).debug("Using HTTP Backend: {s}", .{ @tagName(self.http_mode) });
        switch (self.http_mode)
        {
            // .ChildProcess => return self.authorize_stage_2_process(auth_code),
            // .IguanaTLS => return self.authorize_stage_2_iguana(auth_code),
            .StdLibraryHttp => return self.authorize_stage_2_std(auth_code),
            else => @panic("This HTTP Backend is temporarily disabled")
        }
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
            channelMsg.value.data.?.channel_id != null
        )
        {
            return state.DiscordChannel
            {
                .channel_id = try state.ChannelId.fromSlice(channelMsg.value.data.?.channel_id.?),
                .guild_id =
                    if (guildMsg.value.data.?.guild_id == null)
                        null
                    else
                        try state.GuildId.fromSlice(guildMsg.value.data.?.guild_id.?),
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
                    guild_id = switch (next_token)
                    {
                        std.json.Token.null => "<null>",
                        std.json.Token.string => next_token.string,
                        else => return error.InvalidJsonToken,
                    };
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
                .guild_id =
                    if (std.mem.eql(u8, guild_id.?, "<null>"))
                        null
                    else
                        try state.GuildId.fromSlice(guild_id.?),
            };
        }

        return null;
    }

    pub fn fetch_user_avatars_std(self: *Self) !void
    {
        if (self.state.image_backing_allocator == null) return;

        var api_url_buf: [512]u8 = undefined;

        self.state.all_users_lock.lock();
        defer self.state.all_users_lock.unlock();
        var user_it = self.state.all_users.iterator();
        while (user_it.next()) |user_kv|
        {
            var user: *state.DiscordUser = user_kv.value_ptr;
            if (user.avatar_id == null)
            {
                user.avatar_up_to_date = true;
                continue;
            }

            // deinit unnecessary due to client.deinit calling it
            var temp_bundle = std.crypto.Certificate.Bundle
            {
                .bytes = try self.cert_bundle.?.bytes.clone(self.http_mode.StdLibraryHttp.http_allocator),
            };

            {
                const now_sec = std.time.timestamp();
                var iter = self.cert_bundle.?.map.iterator();
                while (iter.next()) |it|
                {
                    try temp_bundle.parseCert(self.http_mode.StdLibraryHttp.http_allocator, it.value_ptr.*, now_sec);
                }
            }

            var client = std.http.Client
            {
                .allocator = self.http_mode.StdLibraryHttp.http_allocator,
                .ca_bundle = temp_bundle,
                .next_https_rescan_certs = false,
            };
            defer client.deinit();

            var headers = std.http.Headers{ .allocator = self.http_mode.StdLibraryHttp.http_allocator, };
            defer headers.deinit();
            try headers.append("Referer", "https://streamkit.discord.com/overlay/voice");

            var req = try client.request
            (
                .POST,
                try std.Uri.parse
                (
                    try std.fmt.bufPrint
                    (
                        &api_url_buf,
                        AVATAR_API_URL,
                        .{
                            user.user_id.constSlice(),
                            user.avatar_id.?.constSlice(),
                        }
                    )
                ),
                headers,
                .{ .max_redirects = 10 },
            );
            defer req.deinit();

            try start_func(&req, .{});
            try req.finish();
            try req.wait();

            if (req.response.status != .ok)
            {
                return error.DownloadFailed;
            }

            const image = try req.reader().readAllAlloc(self.state.image_backing_allocator.?, AVATAR_MAX_SIZE);
            user.avatar_bytes = image;
            user.avatar_up_to_date = true;
        }
    }

    pub fn fetch_user_avatars(self: *Self) !void
    {
        return self.fetch_user_avatars_std();
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
                                self.state.all_users_lock.lock();
                                defer self.state.all_users_lock.unlock();
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
                            std.mem.eql(u8, self.state.self_user_id.constSlice(), new_user.user_id.constSlice())
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

                            const maybe_user = self.state.all_users.fetchOrderedRemove(dataMsg.value.data.user.id);
                            if (maybe_user) |user|
                            {
                                if (user.value.avatar_bytes) |avatar_bytes|
                                {
                                    if (self.state.image_backing_allocator != null)
                                    {
                                        self.state.image_backing_allocator.?.free(avatar_bytes);
                                    }
                                }
                            }

                            clear =
                                self.state.self_user_id.len > 0 and
                                std.mem.eql(u8, self.state.self_user_id.constSlice(), dataMsg.value.data.user.id);
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

                            self.state.self_user_id.len = 0;
                            try self.state.self_user_id.appendSlice(dataMsg.value.data.user.id);
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
                ws_logger.debug("Stage 2 auth attempt finished.", .{});
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

                try self.fetch_user_avatars();
            },
            .SUBSCRIBE => { },
            .UNSUBSCRIBE => { },
            else => @panic("Unexpected Command")
        }

        return true;
    }

    fn dispatch_handle_message(self: *Self, msg: UnbufferedMessage, buffer: std.ArrayList(u8)) !bool
    {
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
                        return try self.handle_message(buffer.items[0..@truncate(write_length)]);
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

    pub fn recieve_next_msg(self: *Self, timeout_ns: u64) !bool
    {
        self.msg_allocator.reset();
        var msg_buffer = std.ArrayList(u8).init(self.msg_allocator.allocator());
        var msg = try self.conn.receiveIntoWriter(msg_buffer.writer(), 0, timeout_ns);
        return self.dispatch_handle_message(msg, msg_buffer);
    }
};
