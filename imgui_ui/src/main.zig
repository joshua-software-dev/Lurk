const cimgui = @import("cimgui.zig");


pub const DrawIdx = cimgui.ImDrawIdx;
pub const DrawVert = cimgui.ImDrawVert;

var current_imgui_context: ?*cimgui.ImGuiContext = null;


pub fn setup_context(display_x_width: f32, display_y_height: f32) void
{
    current_imgui_context = cimgui.igCreateContext(null);
    cimgui.igSetCurrentContext(current_imgui_context.?);

    const io = cimgui.igGetIO();
    io.*.IniFilename = null;
    io.*.DisplaySize = cimgui.ImVec2{ .x = display_x_width, .y = display_y_height, };
}

pub fn setup_font_text_data(x_width: *i32, y_height: *i32) ![*]u8
{
    const io = cimgui.igGetIO();
    var pixels: ?[*]u8 = undefined;
    var bpp: i32 = 0;
    cimgui.ImFontAtlas_GetTexDataAsRGBA32(io.*.Fonts, @ptrCast(&pixels.?), x_width, y_height, &bpp);

    if (pixels == null) return error.InvalidTexData
    else if (x_width.* < 1 or y_height.* < 1) return error.InvalidFontSize;

    return pixels.?;
}

pub fn set_fonts_tex_ident(id: *anyopaque) void
{
    const io = cimgui.igGetIO();
    cimgui.ImFontAtlas_SetTexID(io.*.Fonts, @ptrCast(id));
}

pub fn get_draw_data_draw_list(draw_data: *cimgui.ImDrawData) []const *cimgui.ImDrawList
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

pub fn destroy_context() bool
{
    if (current_imgui_context) |context|
    {
        cimgui.igDestroyContext(context);
        return true;
    }

    return false;
}

fn draw_frame_contents() void
{
    cimgui.igSeparator();
    cimgui.igText("Hello World!");
    cimgui.igSeparator();
}

pub fn draw_frame() void
{
    // ImGui::SetCurrentContext(data->imgui_context);
    // ImGui::NewFrame();

    // ImGui::SetNextWindowBgAlpha(0.5);
    // ImGui::SetNextWindowSize(data->window_size, ImGuiCond_Always);
    // ImGui::SetNextWindowPos(ImVec2(margin, margin), ImGuiCond_Always);

    // ImGui::Begin("Mesa overlay");

    // ImGui::Separator();

    // ImGui::End();
    // ImGui::EndFrame();
    // ImGui::Render();

    const margin: f32 = 20;

    cimgui.igSetCurrentContext(current_imgui_context.?);
    cimgui.igNewFrame();

    cimgui.igSetNextWindowBgAlpha(0.5);
    cimgui.igSetNextWindowSize(cimgui.ImVec2{ .x = 100, .y = 100, }, cimgui.ImGuiCond_Always);
    cimgui.igSetNextWindowPos
    (
        .{
            .x = margin,
            .y = margin,
        },
        cimgui.ImGuiCond_Always,
        .{ .x = 0, .y = 0, },
    );

    var show_window = true;
    if (cimgui.igBegin("Lurk", &show_window, cimgui.ImGuiWindowFlags_None))
    {
        draw_frame_contents();
    }

    cimgui.igEnd();
    cimgui.igEndFrame();
    cimgui.igRender();
}

pub fn get_draw_data() *cimgui.ImDrawData
{
    return cimgui.igGetDrawData();
}
