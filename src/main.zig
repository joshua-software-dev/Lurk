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

pub fn start_discord_ws_conn(outFile: []const u8) !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var conn: disc.DiscordWsConn = undefined;
    const connUri = try conn.init(allocator);
    std.log.scoped(.WS).info("Connection Success: {+/}", .{ connUri });

    while (true)
    {
        const success = try conn.recieve_next_msg();
        if (!success) break;

        const file = try std.fs.createFileAbsolute(outFile, .{ .lock = .exclusive });
        defer file.close();
        try conn.state.write_users_data_to_file(file);
    }

    conn.close();
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

    // Ensure file can be created before continuing
    const file = try std.fs.createFileAbsolute(outputFile, .{ .lock = .exclusive });
    file.close();

    std.log.scoped(.WS).info("Using output file: {s}", .{ outputFile });
    try start_discord_ws_conn(outputFile);
}
