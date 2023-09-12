const builtin = @import("builtin");
const std = @import("std");

const disc = @import("discord_ws_conn");


const debug = switch (builtin.mode)
{
    .Debug => true,
    else => false,
};

var background_thread: std.Thread = undefined;
var conn: disc.DiscordWsConn = undefined;
var output_buffer: [256*100]u8 = undefined;
pub var output_label: []const u8 = "";
pub var output_lock: std.Thread.Mutex = .{};
var running = false;


pub fn start_discord_conn(allocator: std.mem.Allocator) !void
{
    if (debug) return;

    if (running) return;
    running = true;

    conn = try disc.DiscordWsConn.initMinimalAlloc(allocator, null);
    errdefer conn.close();

    std.log.scoped(.VKLURK).info("Connection Success: {+/}", .{ conn.connection_uri });

    background_thread = try std.Thread.spawn(.{}, handle_message_thread, .{});
}

pub fn handle_message_thread() !void
{
    while (running)
    {
        const success = conn.recieve_next_msg(500)
            catch |err| switch (err)
            {
                std.net.Stream.ReadError.WouldBlock => true,
                std.net.Stream.ReadError.NotOpenForReading => false,
                std.net.Stream.WriteError.NotOpenForWriting => false,
                else => return err
            };

        if (!success) return error.DiscordMessageHandleFailure;

        if (output_lock.tryLock())
        {
            defer output_lock.unlock();

            var stream = std.io.fixedBufferStream(&output_buffer);
            var writter = stream.writer();
            try conn.state.write_users_data_to_write_stream_ascii(writter);
            _ = try writter.write("\x00");
            output_label = stream.getWritten();
        }
    }
}

pub fn stop_discord_conn() void
{
    if (debug) return;

    std.log.scoped(.VKLURK).warn("Received shutdown command, attempting to close connection to discord...", .{});
    running = false;
    if (builtin.os.tag == .windows)
    {
        background_thread.detach();
    }
    else
    {
        background_thread.join();
    }
    conn.close();
    std.log.scoped(.VKLURK).warn("Connection closed.", .{});
}
