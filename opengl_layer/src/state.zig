const builtin = @import("builtin");
const std = @import("std");


pub var first_draw_complete = false;
pub var imgui_ref_count: i32 = 0;
pub var is_using_zink: ?bool = null;

const MAX_MEMORY_ALLOCATION = 1024 * 512; // bytes
const gpa_type = std.heap.GeneralPurposeAllocator
(
    .{
        .enable_memory_limit = true,
        .never_unmap = false,
        .retain_metadata = true,
        .verbose_log = false,
    }
);
var gpa: ?gpa_type = null;
var heap_buf: ?[]u8 = null;
var heap_fba: ?std.heap.FixedBufferAllocator = null;
pub fn get_default_allocator() std.mem.Allocator
{
    switch (builtin.mode)
    {
        .Debug =>
        {
            if (gpa == null)
            {
                gpa = gpa_type{};
                gpa.?.setRequestedMemoryLimit(MAX_MEMORY_ALLOCATION);
            }

            return gpa.?.allocator();
        },
        else =>
        {
            if (heap_fba == null)
            {
                heap_buf = std.heap.c_allocator.alloc(u8, MAX_MEMORY_ALLOCATION) catch @panic("oom");
                heap_fba = std.heap.FixedBufferAllocator.init(heap_buf.?);
            }

            return heap_fba.?.allocator();
        },
    }
}

pub fn free_default_allocator() void
{
    switch (builtin.mode)
    {
        .Debug =>
        {
            if (gpa != null) _ = gpa.?.deinit();
        },
        else =>
        {
            if (heap_buf != null)
            {
                std.heap.c_allocator.free(heap_buf.?);
                heap_buf = null;
                heap_fba = null;
            }
        },
    }
}
