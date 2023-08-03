
pub const Command = enum
{
    DISPATCH,
    AUTHORIZE,
    AUTHENTICATE,
    GET_GUILD,
    GET_GUILDS,
    GET_CHANNEL,
    GET_CHANNELS,
    SUBSCRIBE,
    UNSUBSCRIBE,
    SET_USER_VOICE_SETTINGS,
    SELECT_VOICE_CHANNEL,
    GET_SELECTED_VOICE_CHANNEL,
    SELECT_TEXT_CHANNEL,
    GET_VOICE_SETTINGS,
    SET_VOICE_SETTINGS,
    SET_CERTIFIED_DEVICES,
    SET_ACTIVITY,
    SEND_ACTIVITY_JOIN_INVITE,
    CLOSE_ACTIVITY_REQUEST,
};

pub const Event = enum
{
    READY,
    ERROR,
    GUILD_STATUS,
    GUILD_CREATE,
    CHANNEL_CREATE,
    VOICE_CHANNEL_SELECT,
    VOICE_STATE_CREATE,
    VOICE_STATE_UPDATE,
    VOICE_STATE_DELETE,
    VOICE_SETTINGS_UPDATE,
    VOICE_CONNECTION_STATUS,
    SPEAKING_START,
    SPEAKING_STOP,
    MESSAGE_CREATE,
    MESSAGE_UPDATE,
    MESSAGE_DELETE,
    NOTIFICATION_CREATE,
    ACTIVITY_JOIN,
    ACTIVITY_SPECTATE,
    ACTIVITY_JOIN_REQUEST,
};

pub const Message = struct
{
    cmd: Command,
    evt: ?Event,
    nonce: ?[]const u8,
};

pub const EventReadyData = struct
{
    data: struct { v: u64 },
};

pub const AuthCodeData = struct
{
    data: struct { code: []const u8 },
};

pub const AccessTokenHolder = struct
{
    access_token: []const u8,
};

pub const AuthSuccessData = struct
{
    data: struct { user: struct { id: []const u8 } },
};

const UserVoiceState = struct
{
    deaf: ?bool,
    mute: ?bool,
    self_deaf: ?bool,
    self_mute: ?bool,
    suppress: ?bool,
};

pub const UserInfoAndVoiceState = struct
{
    nick: []const u8,
    volume: u32,
    user: struct
    {
        avatar: ?[]const u8,
        id: []const u8,
    },
    voice_state: UserVoiceState,
};

pub const VoiceStateData = struct
{
    data: ?struct
    {
        guild_id: ?[]const u8,
        id: ?[]const u8,
        name: []const u8,
        voice_states: []UserInfoAndVoiceState,
    },
};

pub const VoiceChannelSelectChannelData = struct
{
    data: ?struct
    {
        channel_id: ?[]const u8,
    },
};

pub const VoiceChannelSelectGuildData = struct
{
    data: ?struct
    {
        guild_id: ?[]const u8,
    },
};

pub const VoiceUpdateUserInfoAndVoiceStateData = struct
{
    data: ?UserInfoAndVoiceState,
};

pub const VoiceSpeakingStartStopData = struct
{
    data: struct { user_id: []const u8, },
};
