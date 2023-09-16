const std = @import("std");

const vkt = @import("vk_types.zig");

const vk = @import("vk");


pub var first_alloc_complete = false;
pub var heap_buf: []u8 = undefined;
pub var heap_fba: std.heap.FixedBufferAllocator = undefined;

// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var device_backing: vkt.DeviceDataHashMap = undefined;
pub var instance_backing: vkt.InstanceDataHashMap = undefined;
pub var swapchain_backing: vkt.SwapchainDataHashMap = undefined;
