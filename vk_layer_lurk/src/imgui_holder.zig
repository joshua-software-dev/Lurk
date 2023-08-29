const zgui = @import("zgui");


pub const DrawVertSize = @sizeOf(zgui.DrawVert);
pub const DrawVertOffsetOfPos = @offsetOf(zgui.DrawVert, "pos");
pub const DrawVertOffsetOfUv = @offsetOf(zgui.DrawVert, "uv");
pub const DrawVertOffsetOfColor = @offsetOf(zgui.DrawVert, "color");


var current_imgui_context: ?zgui.Context = null;


pub fn setup_context(display_x_width: f32, display_y_height: f32) void
{
    current_imgui_context = zgui.zguiCreateContext(null);
    zgui.zguiSetCurrentContext(current_imgui_context.?);

    zgui.io.setIniFilename(null);
    zgui.io.setDisplaySize(display_x_width, display_y_height);
}

pub fn setup_font_text_data(x_width: *i32, y_height: *i32) ![*c]const u32
{
    const result = zgui.io.getFontsTextDataAsRgba32(x_width, y_height);

    if (x_width.* < 1 or y_height.* < 1) return error.InvalidFontSize;
    return result;
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
    zgui.showDemoWindow(null);
}

pub fn draw_frame() void
{
    // ImGui::SetCurrentContext(data->imgui_context);
    // ImGui::NewFrame();

    // ImGui::SetNextWindowBgAlpha(0.5);
    // ImGui::SetNextWindowSize(data->window_size, ImGuiCond_Always);
    // ImGui::SetNextWindowPos(ImVec2(margin, margin), ImGuiCond_Always);

    // ImGui::Begin("Mesa overlay");

    // ImGui::ShowDemoWindow();

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
            .h = 100,
            .w = 100,
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

    if (zgui.begin("Lurk", .{}))
    {
        draw_frame_contents();
    }

    zgui.end();
    zgui.endFrame();
    zgui.render();
}
