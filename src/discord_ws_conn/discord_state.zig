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


var SelfUserId: UserId = UserId.init(0) catch @panic("Failed to init SelfUserId");
var CurrentChannel: DiscordChannel = DiscordChannel
{
    .channel_id = ChannelId.init(0) catch @panic("Failed to init CurrentChannel.channel_id"),
    .guild_id = GuildId.init(0) catch @panic("Failed to init CurrentChannel.guild_id"),
};

pub const DiscordState = struct
{
    const Self = @This();
    self_user_id: UserId,
    current_channel: *DiscordChannel,
    arena: std.heap.ArenaAllocator,
    all_users: std.StringArrayHashMap(DiscordUser),

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void
    {
        self.self_user_id = SelfUserId;
        self.current_channel = &CurrentChannel;

        self.arena = std.heap.ArenaAllocator.init(allocator);
        self.all_users = std.StringArrayHashMap(DiscordUser).init(self.arena.allocator());
    }

    pub fn deinit(self: *Self) void
    {
        self.all_users.deinit();
        self.arena.deinit();
    }

    pub fn free_user_hashmap(self: *Self) void
    {
        _ = self.arena.reset(.free_all);
        self.all_users = std.StringArrayHashMap(DiscordUser).init(self.arena.allocator());
    }

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

    pub fn parse_or_update_one_voice_state(self: *Self, voice_state: msgt.UserInfoAndVoiceState) !*DiscordUser
    {
        var result = try self.all_users.getOrPut(voice_state.user.id);
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

        result.value_ptr.*.volume = voice_state.volume;

        result.value_ptr.*.nickname = try std.BoundedArray(u8, MAX_NICKNAME_LENGTH).init(0);
        try result.value_ptr.*.nickname.?.resize(voice_state.nick.len);
        try result.value_ptr.*.nickname.?.replaceRange(0, voice_state.nick.len, voice_state.nick);

        result.value_ptr.*.avatar_id = null;
        if (voice_state.user.avatar) |avatar|
        {
            result.value_ptr.*.avatar_id = try std.BoundedArray(u8, MAX_AVATAR_ID_LENGTH).init(0);
            try result.value_ptr.*.avatar_id.?.resize(avatar.len);
            try result.value_ptr.*.avatar_id.?.replaceRange(0, avatar.len, avatar);
        }

        return result.value_ptr;
    }

    pub fn parse_voice_state_data(self: *Self, dataMsg: msgt.VoiceStateData) !void
    {
        if (dataMsg.data) |data|
        {
            for (data.voice_states) |voice_state|
            {
                _ = try self.parse_or_update_one_voice_state(voice_state);
            }
        }
    }

    pub fn write_users_data_to_file(self: *Self, out_file: std.fs.File) !void
    {
        try out_file.writeAll("nickname                         | muted | speaking\n");

        var it = self.all_users.iterator();
        while (it.next()) |kv|
        {
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
                        self.arena.allocator(),
                        nick.slice(),
                        32,
                        " "
                    );
                    defer self.arena.allocator().free(paddedNickname);

                    try nickname_buffer.resize(paddedNickname.len);
                    try nickname_buffer.replaceRange(0, paddedNickname.len, paddedNickname);
                }
            }
            else
            {
                try nickname_buffer.resize(32);
                try nickname_buffer.replaceRange(0, 32, "unknown                         ");
            }

            var buf: [1024]u8 = undefined;
            const out = try std.fmt.bufPrint
            (
                &buf,
                "{s} | {: <5} | {}\n",
                .{
                    nickname_buffer.constSlice(),
                    user.muted,
                    user.speaking,
                }
            );
            try out_file.writeAll(out);
        }
    }
};
