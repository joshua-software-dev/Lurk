const builtin = @import("builtin");
const std = @import("std");

const overlay_opts = @import("overlay_opts");
const state = @import("overlay_state.zig");

const zimgui = @import("Zig-ImGui");

pub const font_cache = struct
{
    TexUvWhitePixel: zimgui.Vec2,
    TexUvLines: [64]zimgui.Vec4,
    Glyphs: []const zimgui.FontGlyph,
    TextureX: u32,
    TextureY: u32,
    TextureData: []const u8,
};

const english_only = overlay_opts.english_only;

const primary_font_size: f32 = 20.0;
const emoji_font_size: f32 = 15.0;

fn load_shared_font_from_font_cache() void
{
    const file = std.fs.cwd().openFile("out.imfont.json", .{}) catch @panic("fs error");
    var json_reader = std.json.reader(std.heap.c_allocator, file.reader());
    defer json_reader.deinit();

    const cache_holder = std.json.parseFromTokenSource(font_cache, std.heap.c_allocator, &json_reader, .{}) catch @panic("parse fail");
    defer cache_holder.deinit();

    const cache: font_cache = cache_holder.value;

    state.shared_font_atlas = zimgui.FontAtlas.init_ImFontAtlas();
    var font_config = zimgui.FontConfig.init_ImFontConfig();
    // defer font_config.deinit();
    font_config.FontData = @constCast(@ptrCast(&[_]u8{0}));
    font_config.FontDataSize = 1;
    font_config.SizePixels = 1;
    var font = state.shared_font_atlas.?.AddFont(font_config).?;
    font.FontSize = 20.0;
    font.ConfigData = font_config;
    font.ConfigDataCount = 1;
    font.ContainerAtlas = state.shared_font_atlas.?;

    state.shared_font_atlas.?.ClearTexData();
    // var tex_owned_by_imgui = zimgui.allocator.vtable.alloc(font_config, cache.TextureData.len * 4, @alignOf(*anyopaque), 0).?;
    // // const tex_owned_by_imgui = std.heap.c_allocator.alloc(u32, cache.TextureData.len) catch @panic("oom");
    // var i: usize = 0;
    // for (cache.TextureData) |it|
    // {
    //     // tex_owned_by_imgui[i] = 0xFFFFFF00 + @as(u32, @intCast(it));
    //     tex_owned_by_imgui[i + 0] = 255;
    //     tex_owned_by_imgui[i + 1] = 255;
    //     tex_owned_by_imgui[i + 2] = 255;
    //     tex_owned_by_imgui[i + 3] = it;
    //     i += 4;

    //     // if (i % 4 == 0)
    //     // {
    //     //     tex_owned_by_imgui[i] = it;
    //     // }
    //     // else
    //     // {
    //     //     tex_owned_by_imgui[i] = 255;
    //     // }
    // }

    var tex_vector = zimgui.Vector(u32){};
    tex_vector.reserve(@intCast(cache.TextureData.len));
    for (cache.TextureData, 0..) |it, i|
    {
        tex_vector.insert(@intCast(i), 0xFFFFFF00 + @as(u32, it));
    }

    // const tex_owned_by_imgui = zimgui.allocator.dupe(u8, cache.TextureData) catch @panic("oom");
    state.shared_font_atlas.?.TexPixelsRGBA32 = tex_vector.Data;
    state.shared_font_atlas.?.TexWidth = @intCast(cache.TextureX);
    state.shared_font_atlas.?.TexHeight = @intCast(cache.TextureY);
    state.shared_font_atlas.?.TexUvWhitePixel = cache.TexUvWhitePixel;
    @memcpy(state.shared_font_atlas.?.TexUvLines[0..], cache.TexUvLines[0..]);

    for (cache.Glyphs) |glyph|
    {
        font.AddGlyph(
            font_config,
            glyph.Codepoint,
            glyph.X0,
            glyph.Y0,
            glyph.X1,
            glyph.Y1,
            glyph.U0,
            glyph.V0,
            glyph.U1,
            glyph.V1,
            glyph.AdvanceX,
        );

        font.SetGlyphVisible(glyph.Codepoint, glyph.Visible > 0);
    }

    font.BuildLookupTable();
    state.shared_font_atlas.?.TexReady = true;
    @atomicStore(bool, &state.font_thread_finished, true, .Release);
    @atomicStore(bool, &state.font_load_complete, true, .Release);
    std.log.scoped(.OVERLAY).debug("Cached font loading complete.", .{});
}

pub fn load_shared_font() void
{
    state.shared_font_atlas = zimgui.FontAtlas.init_ImFontAtlas();
    if (english_only)
    {
        _ = state.shared_font_atlas.?.AddFontDefault();
        _ = state.shared_font_atlas.?.Build();
        @atomicStore(bool, &state.font_thread_finished, true, .Release);
        @atomicStore(bool, &state.font_load_complete, true, .Release);
        return;
    }

    const primary_embedded_font_name = "GoNotoKurrent-Regular_v7.0.woff2";
    const primary_embedded_font = @embedFile(primary_embedded_font_name);
    var primary_font_config = zimgui.FontConfig.init_ImFontConfig();
    defer primary_font_config.deinit();
    primary_font_config.EllipsisChar = @as(zimgui.Wchar, 0x0085);
    primary_font_config.GlyphOffset.y = 1.0;
    primary_font_config.OversampleH = 1;
    primary_font_config.OversampleV = 1;
    primary_font_config.PixelSnapH = true;
    primary_font_config.SizePixels = primary_font_size;

    _ = std.fmt.bufPrint
    (
        &primary_font_config.Name,
        "{s}, {d}px\x00",
        .{
            primary_embedded_font_name,
            primary_font_config.SizePixels,
        }
    ) catch @panic("oom loading primary font name");

    // init using imgui's allocator to allow it to free the memory later
    var primary_font_data = zimgui.allocator.dupe(u8, primary_embedded_font) catch @panic("oom loading primary font");
    _ = state.shared_font_atlas.?.AddFontFromMemoryTTFExt
    (
        @ptrCast(primary_font_data),
        @intCast(primary_font_data.len),
        primary_font_config.SizePixels,
        primary_font_config,
        state.shared_font_atlas.?.GetGlyphRangesChineseFull(),
    );

    const emoji_embedded_font_name = "Twemoji.Mozilla.v0.7.0.woff2";
    const emoji_embedded_font = @embedFile(emoji_embedded_font_name);
    var emoji_font_config = zimgui.FontConfig.init_ImFontConfig();
    defer emoji_font_config.deinit();
    emoji_font_config.FontBuilderFlags = 256; // Allow Color Emoji
    emoji_font_config.MergeMode = true;
    emoji_font_config.OversampleH = 1;
    emoji_font_config.OversampleV = 1;
    emoji_font_config.SizePixels = emoji_font_size;

    _ = std.fmt.bufPrint
    (
        &emoji_font_config.Name,
        "{s}, {d}px\x00",
        .{
            emoji_embedded_font_name,
            emoji_font_config.SizePixels,
        }
    ) catch @panic("oom loading emoji font name");

    // init using imgui's allocator to allow it to free the memory later
    var emoji_font_data = zimgui.allocator.dupe(u8, emoji_embedded_font) catch @panic("oom loading emoji font");
    _ = state.shared_font_atlas.?.AddFontFromMemoryTTFExt
    (
        @ptrCast(emoji_font_data),
        emoji_embedded_font.len,
        emoji_font_config.SizePixels,
        emoji_font_config,
        &[_:0]zimgui.Wchar{ 0x1, 0x10FFFF },
    );

    _ = state.shared_font_atlas.?.Build();
    @atomicStore(bool, &state.font_thread_finished, true, .Release);
    @atomicStore(bool, &state.font_load_complete, true, .Release);
    std.log.scoped(.OVERLAY).info("Font loading complete", .{});
}

pub fn load_shared_font_background() !void
{
    std.log.scoped(.OVERLAY).info("Started background font loading thread", .{});
    state.font_thread = try std.Thread.spawn(.{}, load_shared_font, .{});
}
