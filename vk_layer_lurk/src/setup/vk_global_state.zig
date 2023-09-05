const std = @import("std");

const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var device_backing: vkt.DeviceDataMap = vkt.DeviceDataMap.init(0) catch @panic("oom");
pub var instance_backing: vkt.InstanceDataMap = vkt.InstanceDataMap.init(0) catch @panic("oom");
pub var physical_device_backing: vkt.PhysicalDeviceMap = vkt.PhysicalDeviceMap.init(0) catch @panic("oom");
pub var queue_backing: vkt.VkQueueDataMap = vkt.VkQueueDataMap.init(0) catch @panic("oom");
pub var swapchain_backing: vkt.SwapchainDataMap = vkt.SwapchainDataMap.init(0) catch @panic("oom");
