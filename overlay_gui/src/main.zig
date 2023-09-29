const builtin = @import("builtin");
const std = @import("std");

pub const blacklist = @import("blacklist_processes.zig");
pub const disch = @import("discord_conn_holder.zig");
const font = @import("font.zig");
const state = @import("overlay_state.zig");

const disc = @import("discord_ws_conn");
const zimgui = @import("Zig-ImGui");


pub const DrawIdx = zimgui.DrawIdx;
pub const DrawVert = zimgui.DrawVert;

const WindowPosition = enum
{
    TOP_LEFT,
    TOP_RIGHT,
    BOTTOM_LEFT,
    BOTTOM_RIGHT,
};

pub const set_allocator_for_imgui = state.set_allocator_for_imgui;

pub fn load_fonts(use_thread: bool) void
{
    if (state.shared_font_atlas == null)
    {
        if (use_thread)
        {
            font.load_shared_font_background() catch @panic("Failed to start font loading thread");
            return;
        }

        font.load_shared_font();
    }
}

pub fn create_overlay_context(display_x_width: f32, display_y_height: f32) void
{
    if (state.overlay_context == null)
    {
        var old_ctx = zimgui.GetCurrentContext();
        zimgui.SetCurrentContext(null);
        defer zimgui.SetCurrentContext(old_ctx);

        var temp_atlas = zimgui.FontAtlas.init_ImFontAtlas();
        state.overlay_context = zimgui.CreateContextExt(temp_atlas);
        zimgui.SetCurrentContext(state.overlay_context);

        const io = zimgui.GetIO();
        io.Fonts = temp_atlas;
        io.IniFilename = null;
        io.DisplaySize = zimgui.Vec2.init(display_x_width, display_y_height);
    }
}

pub fn use_overlay_context() !?*zimgui.Context
{
    if (state.overlay_context == null) return error.OverlayContextNotCreated;

    var old_ctx = zimgui.GetCurrentContext();
    zimgui.SetCurrentContext(state.overlay_context);
    return old_ctx;
}

pub fn restore_old_context(old_ctx: ?*zimgui.Context) void
{
    zimgui.SetCurrentContext(old_ctx);
}

pub fn destroy_overlay_context() void
{
    if (state.font_thread != null)
    {
        std.log.scoped(.OVERLAY).warn("Waiting for font thread to close...", .{});
        state.font_thread.?.join();
        state.font_thread = null;

        if (state.overlay_context != null)
        {
            const old_ctx = use_overlay_context() catch unreachable;
            defer restore_old_context(old_ctx);
            const im_io = zimgui.GetIO();
            if (im_io.Fonts != null and im_io.Fonts != state.shared_font_atlas) im_io.Fonts.?.deinit();
        }
    }

    if (state.overlay_context != null)
    {
        zimgui.DestroyContextExt(state.overlay_context);
        state.shared_font_atlas.?.deinit();
        state.free_custom_allocator();
    }
}

pub fn setup_font_text_data(x_width: *i32, y_height: *i32) ![*]u8
{
    const im_io = zimgui.GetIO();

    var pixels: ?[*]u8 = undefined;
    im_io.Fonts.?.GetTexDataAsRGBA32(&pixels, x_width, y_height);

    if (pixels == null) return error.InvalidTexData
    else if (x_width.* < 1 or y_height.* < 1) return error.InvalidFontSize;

    return pixels.?;
}

pub fn set_fonts_tex_ident(id: *anyopaque) void
{
    const im_io = zimgui.GetIO();
    im_io.Fonts.?.TexID = id;
}

pub fn get_draw_data() ?*zimgui.DrawData
{
    return zimgui.GetDrawData();
}

pub fn get_draw_data_draw_list(draw_data: *zimgui.DrawData) []const ?*zimgui.DrawList
{
    return draw_data.CmdLists.Data.?[0..draw_data.CmdLists.Size];
}

pub fn get_draw_list_command_buffer(draw_list: *zimgui.DrawList) []const zimgui.DrawCmd
{
    return draw_list.CmdBuffer.Data.?[0..draw_list.CmdBuffer.Size];
}

pub fn get_draw_list_index_buffer(draw_list: *zimgui.DrawList) []const zimgui.DrawIdx
{
    return draw_list.IdxBuffer.Data.?[0..draw_list.IdxBuffer.Size];
}

pub fn get_draw_list_vertex_buffer(draw_list: *zimgui.DrawList) []const zimgui.DrawVert
{
    return draw_list.VtxBuffer.Data.?[0..draw_list.VtxBuffer.Size];
}

fn draw_frame_contents() !void
{
    var alloc_buf: [512]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&alloc_buf);

    if (builtin.mode == .Debug)
    {
        zimgui.SeparatorText("DEBUG 🖥️ デバッグ");
    }
    else
    {
        zimgui.Separator();
    }

    if (disch.conn) |*conn|
    {
        var it = conn.state.all_users.iterator();
        while (it.next()) |kv|
        {
            fba.reset();

            zimgui.PushStyleColor_Vec4(.Button, zimgui.Vec4.init(0.0, 0.0, 0.0, 0.2));
            var style_count: u32 = 1;
            defer zimgui.PopStyleColorExt(@intCast(style_count));

            const user: *disc.DiscordUser = kv.value_ptr;

            // the fba.reset() handles this deallocation
            var safe_name = try fba.allocator().allocSentinel(u8, user.nickname.?.constSlice().len, 0);
            for (user.nickname.?.constSlice(), 0..) |chr, i|
            {
                safe_name[i] =
                    if (chr == '\x00')
                        ' '
                    else if (chr == '#')
                        '+'
                    else
                        chr;
            }

            if (user.muted and user.deafened)
            {
                zimgui.PushStyleColor_Vec4(.Text, zimgui.Vec4.init(128.0 / 255.0, 47.0 / 255.0, 128.0 / 255.0, 0.2));
                style_count += 1;
            }
            else if (user.muted)
            {
                zimgui.PushStyleColor_Vec4(.Text, zimgui.Vec4.init(1.0, 0.0, 0.0, 1.0));
                style_count += 1;
            }
            else if (user.deafened)
            {
                zimgui.PushStyleColor_Vec4(.Text, zimgui.Vec4.init(0.0, 94.0 / 255.0, 1.0, 1.0));
                style_count += 1;
            }
            else if(user.speaking)
            {
                zimgui.PushStyleColor_Vec4(.Text, zimgui.Vec4.init(0.0, 1.0, 0.0, 1.0));
                style_count += 1;
            }

            _ = zimgui.Button(safe_name[0..].ptr);
        }
    }
}

fn set_window_position
(
    display_x: u32,
    display_y: u32,
    window_x: f32,
    window_y: f32,
    position: WindowPosition,
    margin: f32,
)
void
{
    switch (position)
    {
        .TOP_LEFT =>
            zimgui.SetNextWindowPos
            (
                zimgui.Vec2.init(margin, margin)
            ),
        .TOP_RIGHT =>
            zimgui.SetNextWindowPos
            (
                zimgui.Vec2.init(@as(f32, @floatFromInt(display_x)) - window_x - margin, margin)
            ),
        .BOTTOM_LEFT =>
            zimgui.SetNextWindowPos
            (
                zimgui.Vec2.init(margin, @as(f32, @floatFromInt(display_y)) - window_y - margin)
            ),
        .BOTTOM_RIGHT =>
            zimgui.SetNextWindowPos
            (
                zimgui.Vec2.init
                (
                    @as(f32, @floatFromInt(display_x)) - window_x - margin,
                    @as(f32, @floatFromInt(display_y)) - window_y - margin
                )
            ),
    }
}

pub fn is_draw_ready() !void
{
    if (!@atomicLoad(bool, &state.font_load_complete, .Acquire)) return error.FontNotLoaded;
    if (@atomicLoad(bool, &state.font_thread_finished, .Acquire))
    {
        if (state.font_thread != null)
        {
            std.log.scoped(.OVERLAY).debug("Closing font thread before first draw...", .{});
            state.font_thread.?.join();
            state.font_thread = null;
        }
    }

    const im_io = zimgui.GetIO();
    if (im_io.Fonts != state.shared_font_atlas)
    {
        if (im_io.Fonts != null) im_io.Fonts.?.deinit();

        im_io.Fonts = state.shared_font_atlas;
        return error.FontTextureRequiresReload;
    }
}

fn write_font_cache(atlas: *zimgui.FontAtlas) void
{
    const font_out: ?*zimgui.Font = atlas.Fonts.Data.?[0];
    var width: i32 = 0;
    var height: i32 = 0;

    const pixels = setup_font_text_data(&width, &height) catch @panic("Fuck");
    const pixel_array_size: u32 = @intCast(width * height);
    std.debug.assert(pixel_array_size % 4 == 0);

    var out_pixels: []u8 = std.heap.c_allocator.alloc(u8, pixel_array_size / 4) catch @panic("oom");
    defer std.heap.c_allocator.free(out_pixels);

    var ii: usize = 0;
    for (pixels[0..pixel_array_size], 1..) |it, i|
    {
        if (i % 4 == 0)
        {
            out_pixels[ii] = it;
            ii += 1;
        }
    }

    var cache = font.font_cache
    {
        .TexUvWhitePixel = atlas.TexUvWhitePixel,
        .TexUvLines = atlas.TexUvLines,
        .Glyphs = font_out.?.Glyphs.Data.?[0..font_out.?.Glyphs.Size],
        .TextureX = @intCast(width),
        .TextureY = @intCast(height),
        .TextureData = out_pixels,
    };

    var cwd = std.fs.cwd();
    var file = cwd.createFile("out.imfont.json", .{}) catch @panic("fs fail");
    std.json.stringify(cache, .{}, file.writer()) catch @panic("write fail");
    @panic("done");
}

pub fn draw_frame(display_x: u32, display_y: u32) !void
{
    if (disch.conn != null and !disch.conn.?.state.all_users_lock.tryLock())
    {
        return; // Reuse previous frame until data is available
    }
    defer if (disch.conn != null) disch.conn.?.state.all_users_lock.unlock();

    const margin: f32 = 20;

    const im_io = zimgui.GetIO();
    im_io.DisplaySize = zimgui.Vec2.init(@floatFromInt(display_x), @floatFromInt(display_y));
    zimgui.NewFrame();
    zimgui.SetNextWindowBgAlpha(0);

    {
        zimgui.PushStyleVar_Float(.WindowBorderSize, 0);
        defer zimgui.PopStyleVarExt(1);

        const window_size = zimgui.Vec2.init(400, 300);
        zimgui.SetNextWindowSize(window_size);
        set_window_position(display_x, display_y, window_size.x, window_size.y, .TOP_RIGHT, margin);


        var show_window = true;
        if
        (
            zimgui.BeginExt
            (
                "Lurk",
                &show_window,
                zimgui.WindowFlags
                {
                    .NoCollapse = true,
                    .NoResize = true,
                    .NoScrollbar = true,
                    .NoTitleBar = true,
                }
            )
        )
        {
            try draw_frame_contents();
        }
    }

    zimgui.End();
    zimgui.EndFrame();
    zimgui.Render();

    // if (state.shared_font_atlas.?.TexReady and state.shared_font_atlas.?.TexID != null)
    // {
    //     write_font_cache(state.shared_font_atlas.?);
    // }
}
