const builtin = @import("builtin");
const std = @import("std");

const cimgui = @import("cimgui.zig");
const disc = @import("discord_ws_conn");
pub const disch = @import("discord_conn_holder.zig");


pub const DrawIdx = cimgui.ImDrawIdx;
pub const DrawVert = cimgui.ImDrawVert;

pub const ContextContainer = struct
{
    im_context: [*c]cimgui.ImGuiContext,
    im_io: [*c]cimgui.ImGuiIO,
};

const WindowPosition = enum
{
    TOP_LEFT,
    TOP_RIGHT,
    BOTTOM_LEFT,
    BOTTOM_RIGHT,
};

pub fn get_current_context() [*c]cimgui.ImGuiContext
{
    return cimgui.igGetCurrentContext();
}

pub fn set_current_context(ctx: [*c]cimgui.ImGuiContext) void
{
    cimgui.igSetCurrentContext(ctx);
}

pub fn create_context(display_x_width: f32, display_y_height: f32) ContextContainer
{
    var old_ctx = get_current_context();
    set_current_context(null);

    var font_atlas = cimgui.ImFontAtlas_ImFontAtlas();
    var raw_context = cimgui.igCreateContext(font_atlas);
    set_current_context(raw_context);

    cimgui.igPushStyleVar_Float(cimgui.ImGuiStyleVar_WindowBorderSize, 0);

    const io = cimgui.igGetIO();
    io.*.Fonts = font_atlas;
    io.*.IniFilename = null;
    io.*.DisplaySize = cimgui.ImVec2{ .x = display_x_width, .y = display_y_height, };

    set_current_context(old_ctx);

    return .{
        .im_context = raw_context,
        .im_io = io,
    };
}

pub fn setup_font_text_data(im_io: [*c]cimgui.ImGuiIO, x_width: *i32, y_height: *i32) ![*]u8
{
    var pixels: ?[*]u8 = undefined;
    var bpp: i32 = 0;
    cimgui.ImFontAtlas_GetTexDataAsRGBA32(im_io.*.Fonts, @ptrCast(&pixels.?), x_width, y_height, &bpp);

    if (pixels == null) return error.InvalidTexData
    else if (x_width.* < 1 or y_height.* < 1) return error.InvalidFontSize;

    return pixels.?;
}

pub fn set_fonts_tex_ident(im_io: [*c]cimgui.ImGuiIO, id: *anyopaque) void
{
    cimgui.ImFontAtlas_SetTexID(im_io.*.Fonts, @ptrCast(id));
}

pub fn get_draw_data_draw_list(draw_data: cimgui.ImDrawData) []const [*c]cimgui.ImDrawList
{
    const length: i32 = @intCast(draw_data.CmdLists.Size);
    return @ptrCast(draw_data.CmdLists.Data[0..(if (length > -1) @intCast(length) else 0)]);
}

pub fn get_draw_list_command_buffer(draw_list: cimgui.ImDrawList) []const cimgui.ImDrawCmd
{
    const length: i32 = @intCast(draw_list.CmdBuffer.Size);
    return draw_list.CmdBuffer.Data[0..(if (length > -1) @intCast(length) else 0)];
}

pub fn get_draw_list_index_buffer(draw_list: cimgui.ImDrawList) []const cimgui.ImDrawIdx
{
    const length: i32 = @intCast(draw_list.IdxBuffer.Size);
    return draw_list.IdxBuffer.Data[0..(if (length > -1) @intCast(length) else 0)];
}

pub fn get_draw_list_vertex_buffer(draw_list: cimgui.ImDrawList) []const cimgui.ImDrawVert
{
    const length: i32 = @intCast(draw_list.VtxBuffer.Size);
    return draw_list.VtxBuffer.Data[0..(if (length > -1) @intCast(length) else 0)];
}

pub fn destroy_context(im_context: [*c]cimgui.ImGuiContext) void
{
    var current_ctx = get_current_context();
    var unset = im_context == current_ctx;

    cimgui.igDestroyContext(im_context);
    if (unset) set_current_context(null);
}

fn draw_frame_contents() void
{
    var alloc_buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&alloc_buf);
    _ = fba;

    cimgui.igSeparator();

    if (disch.conn) |*conn|
    {
        var it = conn.state.all_users.iterator();
        while (it.next()) |kv|
        {
            const user: *disc.DiscordUser = kv.value_ptr;
            if (user.muted)
            {
                cimgui.igTextColored(.{ .x = 1, .y = 0, .z = 0, .w = 1 }, user.nickname.?.constSlice().ptr);
            }
            else if(user.speaking)
            {
                cimgui.igTextColored(.{ .x = 0, .y = 1, .z = 0, .w = 1 }, user.nickname.?.constSlice().ptr);
            }
            else
            {
                cimgui.igText(user.nickname.?.constSlice().ptr);
            }
        }
    }

    if (builtin.mode == .Debug)
    {
        cimgui.igSeparator();
    }
}

fn set_window_position
(
    display_x: u32,
    display_y: u32,
    window_size: cimgui.ImVec2,
    position: WindowPosition,
    margin: f32,
)
void
{
    switch (position)
    {
        .TOP_LEFT =>
        {
            cimgui.igSetNextWindowPos
            (
                .{
                    .x = margin,
                    .y = margin,
                },
                cimgui.ImGuiCond_Always,
                .{
                    .x = 0,
                    .y = 0,
                },
            );
        },
        .TOP_RIGHT =>
        {
            cimgui.igSetNextWindowPos
            (
                .{
                    .x = @as(f32, @floatFromInt(display_x)) - window_size.x - margin,
                    .y = margin,
                },
                cimgui.ImGuiCond_Always,
                .{
                    .x = 0,
                    .y = 0,
                },
            );
        },
        .BOTTOM_LEFT =>
        {
            cimgui.igSetNextWindowPos
            (
                .{
                    .x = margin,
                    .y = @as(f32, @floatFromInt(display_y)) - window_size.y - margin,
                },
                cimgui.ImGuiCond_Always,
                .{
                    .x = 0,
                    .y = 0,
                },
            );
        },
        .BOTTOM_RIGHT =>
        {
            cimgui.igSetNextWindowPos
            (
                .{
                    .x = @as(f32, @floatFromInt(display_x)) - window_size.x - margin,
                    .y = @as(f32, @floatFromInt(display_y)) - window_size.y - margin,
                },
                cimgui.ImGuiCond_Always,
                .{
                    .x = 0,
                    .y = 0,
                },
            );
        },
    }
}

pub fn draw_frame(io: [*c]cimgui.ImGuiIO, display_x: u32, display_y: u32) !void
{
    _ = try disch.handle_next_message();

    const margin: f32 = 20;

    io.*.DisplaySize = cimgui.ImVec2{ .x = @floatFromInt(display_x), .y = @floatFromInt(display_y), };
    cimgui.igNewFrame();
    cimgui.igSetNextWindowBgAlpha(0);

    const window_size = cimgui.ImVec2{ .x = 400, .y = 300, };
    cimgui.igSetNextWindowSize(window_size, cimgui.ImGuiCond_Always);
    set_window_position(display_x, display_y, window_size, .TOP_RIGHT, margin);

    var show_window = true;
    if
    (
        cimgui.igBegin
        (
            "Lurk",
            &show_window,
            (
                cimgui.ImGuiWindowFlags_NoTitleBar |
                cimgui.ImGuiWindowFlags_NoScrollbar |
                cimgui.ImGuiWindowFlags_NoDecoration
            ),
        )
    )
    {
        draw_frame_contents();
    }

    cimgui.igEnd();
    cimgui.igEndFrame();
    cimgui.igRender();
}

pub fn get_draw_data() [*c]cimgui.ImDrawData
{
    return cimgui.igGetDrawData();
}
