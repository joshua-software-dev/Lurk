const builtin = @import("builtin");
const std = @import("std");

const state = @import("overlay_state.zig");

const disc = @import("discord_ws_conn");


const disable_connection = switch (builtin.mode)
{
    .Debug => true,
    else => false,
};

pub var conn: ?disc.DiscordWsConn = null;
const timeout = 0.5 * std.time.ns_per_ms;
var message_thread: ?std.Thread = null;
var thread_should_run: bool = false;

pub fn start_discord_conn(state_allocator: std.mem.Allocator, image_allocator: ?std.mem.Allocator) !void
{
    if (disable_connection) return;
    if (conn != null) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    conn = try disc.DiscordWsConn.init
    (
        state_allocator,
        image_allocator,
        .{
            .StdLibraryHttp =
            .{
                .bundle = .{ .allocate_new = gpa.allocator() },
                .final_cert_allocator = state_allocator,
                .http_allocator = state_allocator,
                .message_allocator = state_allocator,
            }
        }
    );
    errdefer conn.?.close();
    _ = gpa.deinit();

    std.log.scoped(.OVERLAY).info("Connection Success: {+/}", .{ conn.?.connection_uri });

    if (state.config.?.use_background_network_thread)
    {
        @atomicStore(bool, &thread_should_run, true, .Release);
        message_thread = try std.Thread.spawn(.{}, handle_message_thread, .{});

        std.log.scoped(.OVERLAY).info("Started background discord message thread", .{});
    }
}

pub fn handle_one_message() !void
{
    _ = conn.?.recieve_next_msg(timeout)
        catch |err| switch (err)
        {
            std.net.Stream.ReadError.WouldBlock => {},
            else => std.log.scoped(.OVERLAY).err("{any}", .{ err }),
        };
}

pub fn handle_message_thread() void
{
    while (@atomicLoad(bool, &thread_should_run, .Acquire))
    {
        try handle_one_message();
    }
}

pub fn stop_discord_conn() void
{
    if (disable_connection) return;
    if (conn == null)
    {
        std.log.scoped(.OVERLAY).warn("Discord connection was not started, could not close.", .{});
        return;
    }

    if (message_thread != null)
    {
        std.log.scoped(.OVERLAY).info("Received shutdown command, shutting down message thread...", .{});
        @atomicStore(bool, &thread_should_run, false, .Release);
        message_thread.?.join();
        message_thread = null;
    }

    std.log.scoped(.OVERLAY).info("Closing connection to discord...", .{});
    conn.?.close();
    std.log.scoped(.OVERLAY).info("Connection closed.", .{});
}
