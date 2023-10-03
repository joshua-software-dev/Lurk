const std = @import("std");

const overlay_types = @import("overlay_types.zig");

const zimgui = @import("Zig-ImGui");


pub var config: ?overlay_types.overlay_config = null;
pub var font_load_complete = false;
pub var font_thread_finished = false;
pub var font_thread: ?std.Thread = null;
pub var overlay_context: ?*zimgui.Context = null;
pub var shared_font_atlas: ?*zimgui.FontAtlas = null;

const font_gpa_type = std.heap.GeneralPurposeAllocator
(
    .{
        .enable_memory_limit = false,
        .never_unmap = false,
        .retain_metadata = true,
        .verbose_log = false,
    }
);
var font_gpa: ?font_gpa_type = null;
var imgui_allocator: ?std.mem.Allocator = null;
var imgui_alloc_table: ?std.AutoHashMap(usize, usize) = null;

fn mem_alloc(size: usize, user_data: ?*anyopaque) callconv(.C) ?*anyopaque
{
    _ = user_data;
    const memory = imgui_allocator.?.alignedAlloc(u8, 16, size)
        catch @panic("oom in ImGui alloc");
    imgui_alloc_table.?.put(@intFromPtr(memory.ptr), size)
        catch @panic("oom in ImGui alloc");
    return memory.ptr;
}

fn mem_free(maybe_ptr: ?*anyopaque, user_data: ?*anyopaque) callconv(.C) void
{
    _ = user_data;
    if (maybe_ptr) |ptr|
    {
        if (imgui_alloc_table != null)
        {
            const size = imgui_alloc_table.?.fetchRemove(@intFromPtr(ptr)).?.value;
            const memory = @as([*]align(16) u8, @ptrCast(@alignCast(ptr)))[0..size];
            imgui_allocator.?.free(memory);
        }
    }
}

pub fn set_allocator_for_imgui(maybe_allocator: ?std.mem.Allocator) void
{
    if (imgui_allocator == null)
    {
        if (maybe_allocator == null) font_gpa = .{};

        const allocator =
            if (maybe_allocator == null)
                font_gpa.?.allocator()
            else
                maybe_allocator.?;

        imgui_allocator = allocator;
        imgui_alloc_table = std.AutoHashMap(usize, usize).init(imgui_allocator.?);
        zimgui.SetAllocatorFunctions(@constCast(&mem_alloc), @constCast(&mem_free));
    }
}

pub fn free_custom_allocator() void
{
    if (imgui_alloc_table != null)
    {
        var it = imgui_alloc_table.?.iterator();
        while (it.next()) |kv|
        {
            std.log.scoped(.OVERLAY).debug("Leaked ImGui Memory: {d}|{d}", .{ kv.key_ptr.*, kv.value_ptr.* });
        }
        imgui_alloc_table.?.deinit();
    }
}
