const builtin = @import("builtin");
const std = @import("std");

const vkt = @import("vk_types.zig");

const overlay_gui = @import("overlay_gui");
const vk = @import("vk");


pub var first_alloc_complete = false;

// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var device_backing: vkt.DeviceDataHashMap = undefined;
pub var instance_backing: vkt.InstanceDataHashMap = undefined;
pub var swapchain_backing: vkt.SwapchainDataHashMap = undefined;

pub var device_ref_count: u32 = 0;
pub var instance_ref_count: u32 = 0;
pub var swapchain_ref_count: u32 = 0;

const MAX_MEMORY_ALLOCATION = 1024 * 512; // bytes
const MAX_MEMORY_ALLOCATION_BLACKLISTED = 1024 * 64; // bytes
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
pub fn get_default_allocator(blacklisted: bool) std.mem.Allocator
{
    switch (builtin.mode)
    {
        .Debug =>
        {
            if (gpa == null)
            {
                gpa = .{};
                gpa.?.setRequestedMemoryLimit
                (
                    if (blacklisted)
                        MAX_MEMORY_ALLOCATION_BLACKLISTED
                    else
                        MAX_MEMORY_ALLOCATION
                );
            }

            return gpa.?.allocator();
        },
        else =>
        {
            if (heap_fba == null)
            {
                heap_buf = std.heap.c_allocator.alloc
                (
                    u8,
                    if (blacklisted)
                        MAX_MEMORY_ALLOCATION_BLACKLISTED
                    else
                        MAX_MEMORY_ALLOCATION
                )
                    catch @panic("oom getting default allocator");
                heap_fba = std.heap.FixedBufferAllocator.init(heap_buf.?);
            }

            return heap_fba.?.allocator();
        },
    }
}

pub fn free_default_allocator() void
{
    if (first_alloc_complete)
    {
        device_backing.deinit();
        instance_backing.deinit();
        swapchain_backing.deinit();
    }

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
