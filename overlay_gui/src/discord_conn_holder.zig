const builtin = @import("builtin");
const std = @import("std");

const disc = @import("discord_ws_conn");


const debug = switch (builtin.mode)
{
    .Debug => true,
    else => false,
};

var bundle: ?std.crypto.Certificate.Bundle = null;
pub var conn: ?disc.DiscordWsConn = null;
const timeout = 0.5 * std.time.ns_per_ms;

pub fn alloc_ssl_bundle(temp_allocator: std.mem.Allocator, final_allocator: std.mem.Allocator) !void
{
    if (debug) return;
    bundle = try disc.preload_ssl_certs(temp_allocator, final_allocator);
}

pub fn start_discord_conn(allocator: std.mem.Allocator) !void
{
    if (debug) return;
    if (conn != null) return;

    conn = try disc.DiscordWsConn.initMinimalAlloc(allocator, bundle);
    errdefer conn.close();

    std.log.scoped(.VKLURK).info("Connection Success: {+/}", .{ conn.?.connection_uri });
}

pub fn handle_next_message() !bool
{
    if (conn == null) return false;

    _ = conn.?.recieve_next_msg(timeout)
        catch |err| switch (err)
        {
            std.net.Stream.ReadError.WouldBlock => return false,
            else => return err
        };

    return true;
}

pub fn stop_discord_conn() void
{
    if (debug) return;
    if (conn == null)
    {
        std.log.scoped(.VKLURK).warn("Discord connection was not started, could not close.", .{});
        return;
    }

    std.log.scoped(.VKLURK).warn("Received shutdown command, closing connection to discord...", .{});
    conn.?.close();
    std.log.scoped(.VKLURK).warn("Connection closed.", .{});
}
