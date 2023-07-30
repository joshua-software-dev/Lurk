const builtin = @import("builtin");
const std = @import("std");

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

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var conn: disc.DiscordWsConn = undefined;
    const connUri = conn.init(allocator) catch |err|
    {
        if (err == error.ConnectionRefused)
        {
            @panic("Connection refused");
        }

        return err;
    };

    std.log.scoped(.WS).info("Initial connection to {+/} succeeded.", .{ connUri });

    const tmpDir = try std.fs.openDirAbsolute("/tmp/", .{});

    while (true)
    {
        const success = try conn.recieve_next_msg();
        if (!success) break;

        const file = try tmpDir.createFile("lurk.out", .{ .lock = .exclusive });
        defer file.close();
        try conn.state.write_users_data_to_file(file);
    }

    conn.close();
}
