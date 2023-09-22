const std = @import("std");

const msgt = @import("message_types.zig");

const ziglyph = @import("ziglyph");


pub const MAX_AVATAR_ID_LENGTH = 256;
pub const MAX_CHANNEL_ID_LENGTH = 256;
pub const MAX_GUILD_ID_LENGTH = 256;
pub const MAX_NICKNAME_LENGTH = 256;
pub const MAX_USER_ID_LENGTH = 256;

pub const AvatarId = std.BoundedArray(u8, MAX_AVATAR_ID_LENGTH);
pub const ChannelId = std.BoundedArray(u8, MAX_CHANNEL_ID_LENGTH);
pub const GuildId = std.BoundedArray(u8, MAX_GUILD_ID_LENGTH);
pub const Nickname = std.BoundedArray(u8, MAX_NICKNAME_LENGTH);
pub const UserId = std.BoundedArray(u8, MAX_USER_ID_LENGTH);

pub const DiscordChannel = struct
{
    channel_id: ChannelId,
    guild_id: GuildId,
};

pub const DiscordUser = struct
{
    speaking: bool,
    muted: bool,
    deafened: bool,
    volume: u32,
    nickname: ?Nickname,
    user_id: UserId,
    avatar_id: ?AvatarId,
    // avatar_up_to_date: bool,
    // avatar_bytes: ?std.BoundedArray(u8, 1024*1024),
};

pub const DiscordState = struct
{
    const Self = @This();
    self_user_id: UserId,
    current_channel: DiscordChannel,
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    all_users_lock: std.Thread.Mutex,
    all_users: std.StringArrayHashMapUnmanaged(DiscordUser),

    pub fn init(allocator: std.mem.Allocator) !DiscordState
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var user_map = std.StringArrayHashMapUnmanaged(DiscordUser){};
        try user_map.ensureTotalCapacity(arena.allocator(), 128);

        return .{
            .self_user_id = try UserId.init(0),
            .current_channel = DiscordChannel
            {
                .channel_id = try ChannelId.init(0),
                .guild_id = try GuildId.init(0),
            },
            .backing_allocator = allocator,
            .arena = arena,
            .all_users_lock = .{},
            .all_users = user_map,
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.all_users.deinit(self.arena.allocator());
        self.arena.deinit();
    }

    pub fn free_user_hashmap(self: *Self) void
    {
        self.all_users_lock.lock();
        defer self.all_users_lock.unlock();

        self.all_users.clearRetainingCapacity();
    }

    pub fn set_channel(self: *Self, discord_conn: anytype, new_channel: ?DiscordChannel) !void
    {
        if
        (
            new_channel == null or
            (
                new_channel != null and
                self.current_channel.channel_id.len > 0 and
                (
                    std.mem.eql
                    (
                        u8,
                        self.current_channel.channel_id.slice(),
                        new_channel.?.channel_id.slice()
                    )
                    and
                    std.mem.eql
                    (
                        u8,
                        self.current_channel.guild_id.slice(),
                        new_channel.?.guild_id.slice()
                    )
                )
            )
        )
        {
            return;
        }

        if (self.current_channel.channel_id.len > 0)
        {
            try discord_conn.unsubscribe(.VOICE_STATE_CREATE, self.current_channel);
            try discord_conn.unsubscribe(.VOICE_STATE_UPDATE, self.current_channel);
            try discord_conn.unsubscribe(.VOICE_STATE_DELETE, self.current_channel);
            try discord_conn.unsubscribe(.SPEAKING_START, self.current_channel);
            try discord_conn.unsubscribe(.SPEAKING_STOP, self.current_channel);
        }

        if (new_channel != null)
        {
            try discord_conn.subscribe(.VOICE_STATE_CREATE, new_channel);
            try discord_conn.subscribe(.VOICE_STATE_UPDATE, new_channel);
            try discord_conn.subscribe(.VOICE_STATE_DELETE, new_channel);
            try discord_conn.subscribe(.SPEAKING_START, new_channel);
            try discord_conn.subscribe(.SPEAKING_STOP, new_channel);
        }

        try self
            .current_channel
            .channel_id
            .resize(new_channel.?.channel_id.len);
        try self
            .current_channel
            .channel_id
            .replaceRange(0, new_channel.?.channel_id.len, new_channel.?.channel_id.slice());

        try self
            .current_channel
            .guild_id
            .resize(new_channel.?.guild_id.len);
        try self
            .current_channel
            .guild_id
            .replaceRange(0, new_channel.?.guild_id.len, new_channel.?.guild_id.slice());
    }

    /// Must acquire mutex to use safely
    pub fn get_user_self(self: *Self) ?DiscordUser
    {
        if (self.self_user_id == null) return null;
        const maybeValue = self.all_users.get(self.self_user_id);
        if (maybeValue) |value|
        {
            return value;
        }

        return null;
    }

    /// Must acquire mutex to use safely
    pub fn parse_or_update_one_voice_state(self: *Self, voice_state: msgt.UserInfoAndVoiceState) !*DiscordUser
    {
        var result = self.all_users.getOrPutAssumeCapacity(voice_state.user.id);
        if (!result.found_existing)
        {
            result.value_ptr.* = DiscordUser
            {
                .speaking = false,
                .muted = false,
                .deafened = false,
                .volume = 0,
                .nickname = null,
                .user_id = try std.BoundedArray(u8, MAX_USER_ID_LENGTH).init(0),
                .avatar_id = null,
            };

            try result.value_ptr.*.user_id.resize(voice_state.user.id.len);
            try result.value_ptr.*.user_id.replaceRange(0, voice_state.user.id.len, voice_state.user.id);
            result.key_ptr.* = result.value_ptr.*.user_id.constSlice();
        }

        if (voice_state.voice_state.self_mute != null)
        {
            result.value_ptr.*.muted = voice_state.voice_state.self_mute.?;
        }
        else if (voice_state.voice_state.mute != null)
        {
            result.value_ptr.*.muted = voice_state.voice_state.mute.?;
        }
        else if (voice_state.voice_state.suppress != null)
        {
            result.value_ptr.*.muted = voice_state.voice_state.suppress.?;
        }
        else
        {
            result.value_ptr.*.muted = false;
        }

        if (voice_state.voice_state.self_deaf != null)
        {
            result.value_ptr.*.deafened = voice_state.voice_state.self_deaf.?;
        }
        else if (voice_state.voice_state.deaf != null)
        {
            result.value_ptr.*.deafened = voice_state.voice_state.deaf.?;
        }
        else
        {
            result.value_ptr.*.deafened = false;
        }

        result.value_ptr.*.volume = @intFromFloat(voice_state.volume);

        result.value_ptr.*.nickname = try std.BoundedArray(u8, MAX_NICKNAME_LENGTH).init(0);
        try result.value_ptr.*.nickname.?.appendSlice(voice_state.nick);

        result.value_ptr.*.avatar_id = null;
        if (voice_state.user.avatar) |avatar|
        {
            result.value_ptr.*.avatar_id = try std.BoundedArray(u8, MAX_AVATAR_ID_LENGTH).init(0);
            try result.value_ptr.*.avatar_id.?.resize(avatar.len);
            try result.value_ptr.*.avatar_id.?.replaceRange(0, avatar.len, avatar);
        }

        return result.value_ptr;
    }

    /// Must acquire mutex to use safely
    pub fn parse_voice_state_data(self: *Self, dataMsg: msgt.VoiceStateData) !void
    {
        self.all_users_lock.lock();
        defer self.all_users_lock.unlock();

        if (dataMsg.data) |data|
        {
            for (data.voice_states) |voice_state|
            {
                _ = try self.parse_or_update_one_voice_state(voice_state);
            }
        }
    }

    pub fn write_users_data_to_write_stream(self: *Self, writer: anytype) !void
    {
        self.all_users_lock.lock();
        defer self.all_users_lock.unlock();

        var alloc_buf: [256]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&alloc_buf);
        try writer.print("nickname                         | muted | speaking\n", .{});

        var it = self.all_users.iterator();
        while (it.next()) |kv|
        {
            fba.reset();
            var fba_a = fba.allocator();

            const user: DiscordUser = kv.value_ptr.*;

            var nickname_buffer = try Nickname.init(0);
            if (user.nickname) |nick|
            {
                const unicodeLength = try ziglyph.display_width.strWidth(nick.slice(), .half);
                if (unicodeLength > 32)
                {
                    try nickname_buffer.resize(nick.len);
                    try nickname_buffer.replaceRange(0, nick.len, nick.constSlice());

                    while (try ziglyph.display_width.strWidth(nickname_buffer.constSlice(), .half) > 29)
                    {
                        try nickname_buffer.resize(nickname_buffer.len - 1);
                    }

                    const trimmedLength = nickname_buffer.len;
                    try nickname_buffer.resize(trimmedLength + 3);
                    try nickname_buffer.replaceRange(trimmedLength, 3, "...");
                }
                else
                {
                    var paddedNickname = try ziglyph.display_width.padRight
                    (
                        fba_a,
                        nick.slice(),
                        32,
                        " "
                    );
                    defer fba_a.free(paddedNickname);

                    try nickname_buffer.resize(paddedNickname.len);
                    try nickname_buffer.replaceRange(0, paddedNickname.len, paddedNickname);
                }
            }
            else
            {
                try nickname_buffer.resize(32);
                try nickname_buffer.replaceRange(0, 32, "unknown                         ");
            }

            try writer.print
            (
                "{s} | {: <5} | {}\n",
                .{
                    nickname_buffer.constSlice(),
                    user.muted,
                    user.speaking,
                }
            );
        }
    }

    pub fn write_users_data_to_write_stream_ascii(self: *Self, writer: anytype) !void
    {
        self.all_users_lock.lock();
        defer self.all_users_lock.unlock();

        try writer.print("nickname                         | muted | speaking\n", .{});

        var it = self.all_users.iterator();
        while (it.next()) |kv|
        {
            const user: DiscordUser = kv.value_ptr.*;
            var nickname_buffer = try Nickname.init(0);
            if (user.nickname) |nick|
            {
                try nickname_buffer.resize(MAX_NICKNAME_LENGTH);

                var currentIndex: usize = 0;
                for (nick.constSlice()) |character|
                {
                    if (character < 128) // is ascii
                    {
                        nickname_buffer.set(currentIndex, character);
                        currentIndex += 1;
                    }
                }

                try nickname_buffer.resize(currentIndex);
            }

            try writer.print
            (
                "{s: <32} | {: <5} | {}\n",
                .{
                    nickname_buffer.constSlice(),
                    user.muted,
                    user.speaking,
                }
            );
        }
    }
};

// might be useful at some point
fn get_hash_map_required_bytes(comptime K: type, comptime V: type, comptime buffer_capacity: u32) usize
{
    const Header = struct {
        values: [*]V,
        keys: [*]K,
        capacity: u32,
    };

    const header_align = @alignOf(Header);
    const key_align = if (@sizeOf(K) == 0) 1 else @alignOf(K);
    const val_align = if (@sizeOf(V) == 0) 1 else @alignOf(V);
    const max_align = comptime @max(header_align, key_align, val_align);

    const align_of_metadata = 1;
    _ = align_of_metadata;
    const size_of_metadata = 1;

    const meta_size = @sizeOf(Header) + buffer_capacity * size_of_metadata;

    const keys_start = std.mem.alignForward(usize, meta_size, key_align);
    const keys_end = keys_start + buffer_capacity * @sizeOf(K);

    const vals_start = std.mem.alignForward(usize, keys_end, val_align);
    const vals_end = vals_start + buffer_capacity * @sizeOf(V);

    return std.mem.alignForward(usize, vals_end, max_align);
}
