const std = @import("std");


pub const window_position = enum
{
    TOP_LEFT,
    TOP_RIGHT,
    BOTTOM_LEFT,
    BOTTOM_RIGHT,
};

pub const overlay_config = struct
{
    config_version: u32,
    screen_margin: u32,
    window_position: window_position,
    english_only: bool,
    download_missing_fonts: bool,
    load_fonts_in_background_thread: bool,
    primary_font_path: std.BoundedArray(u8, std.fs.MAX_PATH_BYTES - 1),
    primary_font_size: f32,
    emoji_font_path: std.BoundedArray(u8, std.fs.MAX_PATH_BYTES - 1),
    emoji_font_size: f32,
    use_background_network_thread: bool,
};
