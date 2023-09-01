const std = @import("std");

const vk_layer_stubs = @import("vk_layer_stubs.zig");
const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


pub var command_pool: vk.CommandPool = std.mem.zeroes(vk.CommandPool);
pub var current_image_count: u32 = 0;
pub var descriptor_layout: ?vk.DescriptorSetLayout = null;
pub var descriptor_pool: vk.DescriptorPool = std.mem.zeroes(vk.DescriptorPool);
pub var descriptor_set: ?vk.DescriptorSet = null;
pub var device_queues: vkt.QueueDataBacking = vkt.QueueDataBacking.init(0) catch @panic("oom");
pub var font_already_uploaded: bool = false;
pub var font_image_view: vk.ImageView = std.mem.zeroes(vk.ImageView);
pub var font_image: vk.Image = std.mem.zeroes(vk.Image);
pub var font_mem: vk.DeviceMemory = std.mem.zeroes(vk.DeviceMemory);
pub var font_sampler: ?vk.Sampler = null;
pub var format: ?vk.Format = null;
pub var framebuffers: vkt.FramebufferBacking = vkt.FramebufferBacking.init(0) catch @panic("oom");
pub var graphic_queue: ?*vkt.QueueData = null;
pub var height: ?u32 = null;
pub var image_views: vkt.ImageViewBacking = vkt.ImageViewBacking.init(0) catch @panic("oom");
pub var images: vkt.ImageBacking = vkt.ImageBacking.init(0) catch @panic("oom");
pub var persistent_device: ?vk.Device = null;
pub var physical_mem_props: ?vk.PhysicalDeviceMemoryProperties = null;
pub var pipeline_layout: vk.PipelineLayout = std.mem.zeroes(vk.PipelineLayout);
pub var pipeline: ?vk.Pipeline = null;
pub var previous_draw_data: ?vkt.DrawData = null;
pub var render_pass: vk.RenderPass = std.mem.zeroes(vk.RenderPass);
pub var swapchain: ?*vk.SwapchainKHR = null;
pub var upload_font_buffer_mem: vk.DeviceMemory = std.mem.zeroes(vk.DeviceMemory);
pub var upload_font_buffer: vk.Buffer = std.mem.zeroes(vk.Buffer);
pub var width: ?u32 = null;

// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var base_wrapper: ?vkt.LayerBaseWrapper = null;
pub var device_wrapper: ?vkt.LayerDeviceWrapper = null;
pub var init_wrapper: ?vk_layer_stubs.LayerInitWrapper = null;
pub var instance_wrapper: ?vkt.LayerInstanceWrapper = null;
