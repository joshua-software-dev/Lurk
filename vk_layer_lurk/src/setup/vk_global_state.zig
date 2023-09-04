const std = @import("std");

const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var base_wrapper: ?vkt.LayerBaseWrapper = null;
pub var device_backing: vkt.DeviceDataQueue = vkt.DeviceDataQueue.init(0) catch @panic("oom");
pub var instance_wrapper: ?vkt.LayerInstanceWrapper = null;
