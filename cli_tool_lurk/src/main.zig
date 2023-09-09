const builtin = @import("builtin");
const std = @import("std");

const clap = @import("clap");

const disc = @import("discord_ws_conn");


pub const std_options = struct
{
    pub const log_scope_levels: []const std.log.ScopeLevel =
    &[_]std.log.ScopeLevel
    {
        .{
            .scope = .WS,
            .level = switch (builtin.mode)
            {
                .Debug => .debug,
                else => .info,
            }
        },
    };
};

var conn: ?disc.DiscordWsConn = null;

fn handle_signal(signal: c_int) callconv(.C) void
{
    std.log.scoped(.WS).info
    (
        "Received Signal: {d}|{s}",
        .{
            signal,
            switch(signal)
            {
                std.os.linux.SIG.INT => "SIGINT",
                std.os.linux.SIG.TERM => "SIGTERM",
                else => "Unknown"
            },
        }
    );

    if (conn) |*c|
    {
        std.log.scoped(.WS).info("Closing connection...", .{});
        c.close();
    }
}

pub fn start_discord_ws_conn(outFile: []const u8) !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    errdefer _ = gpa.detectLeaks();

    conn = try disc.DiscordWsConn.initMinimalAlloc(allocator, null, 100);
    errdefer conn.?.close();
    if (builtin.os.tag == .linux)
    {
        std.log.scoped(.WS).info("Setting up Linux close signal handlers...", .{});
        try std.os.sigaction
        (
            std.os.linux.SIG.INT,
            &std.os.Sigaction{
                .handler = .{  .handler = handle_signal, },
                .mask = std.os.empty_sigset,
                .flags = 0,
            },
            null
        );

        try std.os.sigaction
        (
            std.os.linux.SIG.TERM,
            &std.os.Sigaction{
                .handler = .{  .handler = handle_signal, },
                .mask = std.os.empty_sigset,
                .flags = 0,
            },
            null
        );
    }

    var stdout: ?std.fs.File = null;
    if (builtin.os.tag == .windows)
    {
        stdout = std.io.getStdOut();
    }

    std.log.scoped(.WS).info("Connection Success: {+/}", .{ conn.?.connection_uri, });

    while (true)
    {
        const success = conn.?.recieve_next_msg()
            catch |err| switch (err)
            {
                std.net.Stream.ReadError.WouldBlock => true,
                std.net.Stream.ReadError.NotOpenForReading => false,
                std.net.Stream.ReadError.NotOpenForWriting => false,
                else => return err
            };

        if (!success) break;

        if (builtin.os.tag == .windows)
        {
            try conn.?.state.write_users_data_to_write_stream_ascii(stdout.?.writer());
        }
        else
        {
            const file = try std.fs.createFileAbsolute(outFile, .{ .lock = .exclusive });
            defer file.close();
            try conn.?.state.write_users_data_to_write_stream_ascii(file.writer());
        }
    }
}

pub fn main() !void
{
    const params = comptime clap.parseParamsComptime
    (
        \\-h, --help          Display this help and exit.
        \\-o, --out <OUTFILE> Override file current status is written to (Default: '/tmp/lurk.out')
    );

    const parsers = comptime
    .{
        .OUTFILE = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse
    (
        clap.Help,
        &params,
        parsers,
        .{ .diagnostic = &diag, }
    )
    catch |err|
    {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    var outputFile: []const u8 = "/tmp/lurk.out";
    if (res.args.help != 0)
    {
        return clap.help(std.io.getStdOut().writer(), clap.Help, &params, .{});
    }
    else if (res.args.out) |out|
    {
        outputFile = out;
    }

    if (builtin.os.tag != .windows)
    {
        // Ensure file can be created before continuing
        const file = try std.fs.createFileAbsolute(outputFile, .{ .lock = .exclusive });
        file.close();
    }

    std.log.scoped(.WS).info("Using output file: {s}", .{ outputFile });
    try start_discord_ws_conn(outputFile);
}
