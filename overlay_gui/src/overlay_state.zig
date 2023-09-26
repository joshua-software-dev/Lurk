const std = @import("std");

const zimgui = @import("Zig-ImGui");


pub var font_load_complete = false;
pub var font_thread_finished = false;
pub var font_thread: ?std.Thread = null;
pub var overlay_context: ?*zimgui.Context = null;
pub var shared_font_atlas: ?*zimgui.FontAtlas = null;
