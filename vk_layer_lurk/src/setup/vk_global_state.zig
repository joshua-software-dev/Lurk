const std = @import("std");

const vkl = @import("vk_layer_stubs.zig");
const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


pub var command_pool: ?vk.CommandPool = null;
pub var descriptor_layout: ?vk.DescriptorSetLayout = null;
pub var descriptor_pool: ?vk.DescriptorPool = null;
pub var descriptor_set: ?vk.DescriptorSet = null;
pub var font_already_uploaded: bool = false;
pub var font_image_view: ?vk.ImageView = null;
pub var font_image: ?vk.Image = null;
pub var font_mem: ?vk.DeviceMemory = null;
pub var font_sampler: ?vk.Sampler = null;
pub var format: ?vk.Format = null;
pub var graphic_queue: ?vkt.QueueData = null;
pub var height: ?u32 = null;
pub var image_count: ?u32 = null;
pub var persistent_device: ?vk.Device = null;
pub var pipeline_layout: ?vk.PipelineLayout = null;
pub var pipeline: ?vk.Pipeline = null;
pub var previous_draw_data: ?vkt.DrawData = null;
pub var render_pass: ?vk.RenderPass = null;
pub var swapchain: ?vk.SwapchainKHR = null;
pub var upload_font_buffer_mem: ?vk.DeviceMemory = null;
pub var upload_font_buffer: ?vk.Buffer = null;
pub var width: ?u32 = null;

pub var device_queues: vkt.QueueDataBacking = vkt.QueueDataBacking.init(0) catch @panic("oom");
pub var framebuffers: vkt.FramebufferBacking = vkt.FramebufferBacking.init(0) catch @panic("oom");
pub var image_views: vkt.ImageViewBacking = vkt.ImageViewBacking.init(0) catch @panic("oom");
pub var images: vkt.ImageBacking = vkt.ImageBacking.init(0) catch @panic("oom");

// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var base_wrapper: ?vkt.LayerBaseWrapper = null;
pub var device_wrapper: ?vkt.LayerDeviceWrapper = null;
pub var init_wrapper: ?vkl.LayerInitWrapper = null;
pub var instance_wrapper: ?vkt.LayerInstanceWrapper = null;
