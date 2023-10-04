const builtin = @import("builtin");
const std = @import("std");

const overlay_opts = @import("overlay_opts");
const state = @import("overlay_state.zig");

const zimgui = @import("Zig-ImGui");


const emoji_font_uri = std.Uri.parse
(
    "https://github.com/joshua-software-dev/Lurk/releases/download/DefaultFonts/Twemoji.Mozilla.v0.7.0.woff2"
)
    catch unreachable;
const emoji_font_sha256sum = sha256sum_to_array("de10ef1cca0407b83048536b9e27294099df00bf8deb6e429f30aae6011629c4");
const primary_font_uri = std.Uri.parse
(
    "https://github.com/joshua-software-dev/Lurk/releases/download/DefaultFonts/GoNotoKurrent-Regular_v7.0.woff2"
)
    catch unreachable;
const primary_font_sha256sum = sha256sum_to_array("7707f03fdac86c686e715d5e9ec03f4ce38a897ec05fcb973ae84f5d67ffe406");

pub const font_cache = struct
{
    TexUvWhitePixel: zimgui.Vec2,
    TexUvLines: [64]zimgui.Vec4,
    Glyphs: []const zimgui.FontGlyph,
    TextureX: u32,
    TextureY: u32,
    TextureData: []const u8,
};

fn sha256sum_to_array(comptime sha256sum: []const u8) [32]u8
{
    var expected_bytes: [sha256sum.len / 2]u8 = undefined;
    for (&expected_bytes, 0..) |*r, i| {
        r.* = std.fmt.parseInt(u8, sha256sum[2 * i .. 2 * i + 2], 16) catch unreachable;
    }
    return expected_bytes;
}

fn load_shared_font_from_font_cache() void
{
    const file = std.fs.cwd().openFile("out.imfont.json", .{})
        catch @panic("fs error");
    var json_reader = std.json.reader(std.heap.c_allocator, file.reader());
    defer json_reader.deinit();

    const cache_holder = std.json.parseFromTokenSource(font_cache, std.heap.c_allocator, &json_reader, .{})
        catch @panic("parse fail");
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

    var tex_vector: zimgui.Vector(u32) = .{};
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

fn start_0110(req: *std.http.Client.Request, args: anytype) !void
{
    _ = args;
    try req.start();
}

fn start_0120(req: *std.http.Client.Request, args: anytype) !void
{
    try req.start(args);
}

const start_func =
    if (builtin.zig_version.order(std.SemanticVersion.parse("0.11.0") catch unreachable) == .gt)
        start_0120
    else
        start_0110;

fn download_font
(
    allocator: std.mem.Allocator,
    uri: std.Uri,
    out_path: []const u8,
    expected_hash: [32]u8,
)
!void
{
    var hash = std.crypto.hash.sha2.Sha256.init(.{});

    {
        const out_fd = try std.fs.createFileAbsolute(out_path, .{ .read = true, });
        defer out_fd.close();

        var client: std.http.Client = .{ .allocator = allocator, };
        defer client.deinit();

        var headers: std.http.Headers = .{ .allocator = allocator, };
        defer headers.deinit();

        var req = try client.request
        (
            .GET,
            uri,
            headers,
            .{ .max_redirects = 10 },
        );
        defer req.deinit();

        try start_func(&req, .{});
        try req.finish();
        try req.wait();

        if (req.response.status != .ok)
        {
            return error.DownloadFailed;
        }

        {
            var buf: [1024]u8 = undefined;
            var reader = req.reader();
            var writer = out_fd.writer();
            while (true)
            {
                const bytes_read = try reader.read(&buf);
                if (bytes_read == 0) break;

                _ = try writer.write(buf[0..bytes_read]);
                hash.update(buf[0..bytes_read]);
            }
            try out_fd.sync();
        }
    }

    var out: [32]u8 = undefined;
    hash.final(out[0..]);

    if (!std.mem.eql(u8, &out, &expected_hash)) return error.DownloadHashCheckFailed;
}

pub fn load_shared_font(allocator: std.mem.Allocator) void
{
    if (state.config.?.english_only)
    {
        _ = state.shared_font_atlas.?.AddFontDefault();
        _ = state.shared_font_atlas.?.Build();
        std.log.scoped(.OVERLAY).warn("Using english only mode, expect potential rendering errors", .{});
        @atomicStore(bool, &state.font_thread_finished, true, .Release);
        @atomicStore(bool, &state.font_load_complete, true, .Release);
        return;
    }

    if (state.config.?.download_missing_fonts)
    {
        const primary_font_exists = blk: {
            std.fs.accessAbsolute(state.config.?.primary_font_path.constSlice(), .{})
                catch break :blk false;
            break :blk true;
        };
        if (!primary_font_exists)
        {
            std.log.scoped(.OVERLAY).warn
            (
                "Primary font not found: {s}",
                .{ state.config.?.primary_font_path.constSlice() }
            );
            std.log.scoped(.OVERLAY).warn("Downloading primary font from: {+/}", .{ primary_font_uri });
            download_font
            (
                allocator,
                primary_font_uri,
                state.config.?.primary_font_path.constSlice(),
                primary_font_sha256sum,
            )
                catch |err| std.debug.panic("Failed to download primary font: {any}", .{ err });
        }

        const emoji_font_exists = blk: {
            std.fs.accessAbsolute(state.config.?.emoji_font_path.constSlice(), .{})
                catch break :blk false;
            break :blk true;
        };
        if (!emoji_font_exists)
        {
            std.log.scoped(.OVERLAY).warn
            (
                "Emoji font not found: {s}",
                .{ state.config.?.emoji_font_path.constSlice() }
            );
            std.log.scoped(.OVERLAY).warn("Downloading emoji font from: {+/}", .{ emoji_font_uri });
            download_font
            (
                allocator,
                emoji_font_uri,
                state.config.?.emoji_font_path.constSlice(),
                emoji_font_sha256sum,
            )
                catch |err| std.debug.panic("Failed to download emoji font: {any}", .{ err });
        }
    }

    var primary_font_config = zimgui.FontConfig.init_ImFontConfig();
    defer primary_font_config.deinit();
    primary_font_config.EllipsisChar = @as(zimgui.Wchar, 0x0085);
    primary_font_config.GlyphOffset.y = 1.0;
    primary_font_config.OversampleH = 1;
    primary_font_config.OversampleV = 1;
    primary_font_config.PixelSnapH = true;
    primary_font_config.SizePixels = state.config.?.primary_font_size;

    {
        const primary_font_name = std.fs.path.basename(state.config.?.primary_font_path.constSlice());
        _ = std.fmt.bufPrint
        (
            &primary_font_config.Name,
            "{s}, {d}px\x00",
            .{
                primary_font_name[0..@min(primary_font_name.len, 32)],
                primary_font_config.SizePixels,
            }
        )
            catch @panic("oom loading primary font name");
    }

    {
        const primary_font_posix_path = std.os.toPosixPath(state.config.?.primary_font_path.constSlice())
            catch @panic("Failed to get posix path for primary font.");

        // init using imgui's allocator to allow it to free the memory later
        _ = state.shared_font_atlas.?.AddFontFromFileTTFExt
        (
            &primary_font_posix_path,
            primary_font_config.SizePixels,
            primary_font_config,
            state.shared_font_atlas.?.GetGlyphRangesChineseFull(),
        );
    }

    var emoji_font_config = zimgui.FontConfig.init_ImFontConfig();
    defer emoji_font_config.deinit();
    emoji_font_config.FontBuilderFlags = 256; // Allow Color Emoji
    emoji_font_config.MergeMode = true;
    emoji_font_config.OversampleH = 1;
    emoji_font_config.OversampleV = 1;
    emoji_font_config.SizePixels = state.config.?.emoji_font_size;

    {
        const emoji_font_name = std.fs.path.basename(state.config.?.emoji_font_path.constSlice());
        _ = std.fmt.bufPrint
        (
            &emoji_font_config.Name,
            "{s}, {d}px\x00",
            .{
                emoji_font_name[0..@min(emoji_font_name.len, 32)],
                emoji_font_config.SizePixels,
            }
        )
            catch @panic("oom loading emoji font name");
    }

    {
        const emoji_font_posix_path = std.os.toPosixPath(state.config.?.emoji_font_path.constSlice())
            catch @panic("Failed to get posix path for emoji font.");

        // init using imgui's allocator to allow it to free the memory later
        _ = state.shared_font_atlas.?.AddFontFromFileTTFExt
        (
            &emoji_font_posix_path,
            emoji_font_config.SizePixels,
            emoji_font_config,
            &@as([2:0]zimgui.Wchar, .{ 0x1, 0x10FFFF, })
        );
    }

    _ = state.shared_font_atlas.?.Build();
    @atomicStore(bool, &state.font_thread_finished, true, .Release);
    @atomicStore(bool, &state.font_load_complete, true, .Release);
    std.log.scoped(.OVERLAY).info("Font loading complete", .{});
}

pub fn load_shared_font_background(allocator: std.mem.Allocator) !void
{
    if (state.font_thread == null)
    {
        std.log.scoped(.OVERLAY).info("Started background font loading thread", .{});
        state.font_thread = try std.Thread.spawn(.{}, load_shared_font, .{ allocator });
    }
}
