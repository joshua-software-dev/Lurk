const std = @import("std");

const overlay_opts = @import("overlay_opts");
const state = @import("overlay_state.zig");

const zimgui = @import("Zig-ImGui");


const english_only = overlay_opts.english_only;

const primary_font_size: f32 = 20.0;
var primary_font_config: ?*zimgui.FontConfig = null;

const emoji_font_size: f32 = 15.0;
var emoji_font_config: ?*zimgui.FontConfig = null;

pub fn load_shared_font() void
{
    state.shared_font_atlas = zimgui.FontAtlas.init_ImFontAtlas();
    if (english_only)
    {
        state.shared_font_atlas.?.AddFontDefault();
        _ = state.shared_font_atlas.?.Build();
        @atomicStore(bool, &state.font_thread_finished, true, .Release);
        @atomicStore(bool, &state.font_load_complete, true, .Release);
        return;
    }

    const primary_embedded_font_name = "GoNotoKurrent-Regular_v7.0.woff2";
    const primary_embedded_font = @embedFile(primary_embedded_font_name);
    primary_font_config = zimgui.FontConfig.init_ImFontConfig();
    primary_font_config.?.EllipsisChar = @as(zimgui.Wchar, 0x0085);
    primary_font_config.?.GlyphOffset.y = 1.0;
    primary_font_config.?.OversampleH = 1;
    primary_font_config.?.OversampleV = 1;
    primary_font_config.?.PixelSnapH = true;
    primary_font_config.?.SizePixels = primary_font_size;

    _ = std.fmt.bufPrint
    (
        &primary_font_config.?.Name,
        "{s}, {d}px\x00",
        .{
            primary_embedded_font_name,
            primary_font_config.?.SizePixels,
        }
    ) catch @panic("oom");

    // init using imgui's allocator to allow it to free the memory later
    var primary_font_data = zimgui.allocator.dupe(u8, primary_embedded_font) catch @panic("oom loading primary font");
    _ = state.shared_font_atlas.?.AddFontFromMemoryTTFExt
    (
        @ptrCast(primary_font_data),
        @intCast(primary_font_data.len),
        primary_font_config.?.SizePixels,
        primary_font_config.?,
        state.shared_font_atlas.?.GetGlyphRangesChineseFull(),
    );

    const emoji_embedded_font_name = "Twemoji.Mozilla.v0.7.0.woff2";
    const emoji_embedded_font = @embedFile(emoji_embedded_font_name);
    emoji_font_config = zimgui.FontConfig.init_ImFontConfig();
    emoji_font_config.?.FontBuilderFlags = 256; // Allow Color Emoji
    emoji_font_config.?.MergeMode = true;
    emoji_font_config.?.OversampleH = 1;
    emoji_font_config.?.OversampleV = 1;
    emoji_font_config.?.SizePixels = emoji_font_size;

    _ = std.fmt.bufPrint
    (
        &emoji_font_config.?.Name,
        "{s}, {d}px\x00",
        .{
            emoji_embedded_font_name,
            emoji_font_config.?.SizePixels,
        }
    ) catch @panic("oom");

    // init using imgui's allocator to allow it to free the memory later
    var emoji_font_data = zimgui.allocator.dupe(u8, emoji_embedded_font) catch @panic("oom loading primary font");
    _ = state.shared_font_atlas.?.AddFontFromMemoryTTFExt
    (
        @ptrCast(emoji_font_data),
        emoji_embedded_font.len,
        emoji_font_config.?.SizePixels,
        emoji_font_config.?,
        &[_:0]zimgui.Wchar{ 0x1, 0x10FFFF },
    );

    _ = state.shared_font_atlas.?.Build();
    @atomicStore(bool, &state.font_thread_finished, true, .Release);
    @atomicStore(bool, &state.font_load_complete, true, .Release);
    std.log.scoped(.OVERLAY).debug("Font loading complete.", .{});
}

pub fn load_shared_font_background() !void
{
    state.font_thread = try std.Thread.spawn(.{}, load_shared_font, .{});
}
