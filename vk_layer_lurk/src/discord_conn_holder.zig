const std = @import("std");

const disc = @import("discord_ws_conn");


var background_thread: std.Thread = undefined;
var conn: disc.DiscordWsConn = undefined;
var running = false;
var stdout: ?std.fs.File = null;


pub fn start_discord_conn(allocator: std.mem.Allocator) !void
{
    if (running) return;
    running = true;

    const connUri = try conn.init(allocator, 100);
    errdefer conn.close();

    std.log.scoped(.WS).info("Connection Success: {+/}", .{ connUri });
    stdout = std.io.getStdOut();

    background_thread = try std.Thread.spawn(.{}, handle_message_thread, .{});
}

pub fn handle_message_thread() !void
{
    while (running)
    {
        const success = conn.recieve_next_msg()
            catch |err|
                if (err == std.net.Stream.ReadError.WouldBlock)
                    true
                else
                    return err;

        if (!success) return error.DiscordMessageHandleFailure;

        if (stdout) |out|
        {
            try conn.state.write_users_data_to_write_stream(out.writer());
        }
    }
}

pub fn stop_discord_conn() void
{
    std.log.scoped(.WS).warn("Received shutdown command, attempting to close connection to discord...", .{});
    running = false;
    conn.close();
    background_thread.join();
    std.log.scoped(.WS).warn("Connection closed.", .{});
}
