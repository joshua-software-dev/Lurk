const std = @import("std");

const vkl = @import("vk_layer_stubs.zig");
const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


pub var graphic_queue: ?vkt.QueueData = null;
pub var persistent_device: ?vk.Device = null;
pub var previous_draw_data: ?vkt.DrawData = null;

pub var device_queues: vkt.QueueDataBacking = vkt.QueueDataBacking.init(0) catch @panic("oom");
var buf: [1024*64]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buf);
pub var swapchain_backing = vkt.SwapchainHashMapBacking.init(fba.allocator());

// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var base_wrapper: ?vkt.LayerBaseWrapper = null;
pub var device_wrapper: ?vkt.LayerDeviceWrapper = null;
pub var init_wrapper: ?vkl.LayerInitWrapper = null;
pub var instance_wrapper: ?vkt.LayerInstanceWrapper = null;
