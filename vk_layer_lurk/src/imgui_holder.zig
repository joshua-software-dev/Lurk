const zgui = @import("zgui");


pub const DrawIdx = zgui.DrawIdx;
pub const DrawVert = zgui.DrawVert;
pub const DrawIdxSize = @sizeOf(DrawIdx);
pub const DrawVertSize = @sizeOf(DrawVert);
pub const DrawVertOffsetOfPos = @offsetOf(DrawVert, "pos");
pub const DrawVertOffsetOfUv = @offsetOf(DrawVert, "uv");
pub const DrawVertOffsetOfColor = @offsetOf(DrawVert, "color");


var current_imgui_context: ?zgui.Context = null;


pub fn setup_context(display_x_width: f32, display_y_height: f32) void
{
    current_imgui_context = zgui.zguiCreateContext(null);
    zgui.zguiSetCurrentContext(current_imgui_context.?);

    zgui.io.setIniFilename(null);
    zgui.io.setDisplaySize(display_x_width, display_y_height);
}

pub fn setup_font_text_data(x_width: *i32, y_height: *i32) ![*]u8
{
    const result = zgui.io.getFontsTextDataAsRgba32(x_width, y_height);

    if (result == null) return error.InvalidTexData
    else if (x_width.* < 1 or y_height.* < 1) return error.InvalidFontSize;

    return @ptrCast(@constCast(result));
}

pub fn set_fonts_tex_ident(id: *anyopaque) void
{
    zgui.io.setFontsTexId(@ptrCast(id));
}

pub fn get_draw_list_command_buffer(draw_list: zgui.DrawList) []const zgui.DrawCmd
{
    const length = draw_list.getCmdBufferLength();
    return draw_list.getCmdBufferData()[0..(if (length > -1) @intCast(length) else 0)];
}

pub fn get_draw_list_index_buffer(draw_list: zgui.DrawList) []const DrawIdx
{
    const length = draw_list.getIndexBufferLength();
    return draw_list.getIndexBufferData()[0..(if (length > -1) @intCast(length) else 0)];
}

pub fn get_draw_list_vertex_buffer(draw_list: zgui.DrawList) []const DrawVert
{
    const length = draw_list.getVertexBufferLength();
    return draw_list.getVertexBufferData()[0..(if (length > -1) @intCast(length) else 0)];
}

pub fn destroy_context() bool
{
    if (current_imgui_context) |context|
    {
        zgui.zguiDestroyContext(context);
        return true;
    }

    return false;
}

fn draw_frame_contents() void
{
    zgui.separator();
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

    zgui.zguiSetCurrentContext(current_imgui_context.?);
    zgui.newFrame();

    zgui.setNextWindowBgAlpha(.{ .alpha = 0.5, });
    zgui.setNextWindowSize
    (
        .{
            .h = 600,
            .w = 600,
            .cond = .always,
        },
    );
    zgui.setNextWindowPos
    (
        .{
            .cond = .always,
            .x = margin,
            .y = margin,
        }
    );

    var show_window = true;
    if (zgui.begin("Lurk", .{ .popen = &show_window, }))
    {
        draw_frame_contents();
    }

    zgui.end();
    zgui.endFrame();
    zgui.render();
}

pub fn get_draw_data() zgui.DrawData
{
    return zgui.getDrawData();
}
