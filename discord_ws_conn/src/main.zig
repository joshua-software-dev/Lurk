const state = @import("discord_state.zig");


pub const DiscordUser = state.DiscordUser;
pub const DiscordWsConn = @import("discord_conn.zig").DiscordWsConn;
pub const preload_ssl_certs = @import("preload_ssl_certs.zig").preload_ssl_certs;
