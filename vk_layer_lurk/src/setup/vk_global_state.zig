const std = @import("std");

const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


var buf: [1024 * 256]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buf);

// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var device_backing: vkt.DeviceDataHashMap = vkt.DeviceDataHashMap.init(fba.allocator());
pub var instance_backing: vkt.InstanceDataHashMap = vkt.InstanceDataHashMap.init(fba.allocator());
pub var physical_device_backing: vkt.PhyDevToInstanceHashMap = vkt.PhyDevToInstanceHashMap.init(fba.allocator());
pub var queue_backing: vkt.VkQueueDataHashMap = vkt.VkQueueDataHashMap.init(fba.allocator());
pub var swapchain_backing: vkt.SwapchainDataHashMap = vkt.SwapchainDataHashMap.init(fba.allocator());
