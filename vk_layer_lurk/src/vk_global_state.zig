const std = @import("std");

const vk = @import("vk.zig");


pub const DrawData = struct
{
    command_buffer: vk.CommandBuffer,

    cross_engine_semaphore: vk.Semaphore,

    semaphore: vk.Semaphore,
    fence: vk.Fence,

    vertex_buffer: vk.Buffer,
    vertex_buffer_mem: vk.DeviceMemory,
    vertex_buffer_size: vk.DeviceSize,

    index_buffer: vk.Buffer,
    index_buffer_mem: vk.DeviceMemory,
    index_buffer_size: vk.DeviceSize,
};
pub const QueueData = struct
{
    queue_family_index: u32,
    queue_flags: vk.QueueFlags,
    queue: vk.Queue,
    fence: vk.Fence,
};

pub const LayerDeviceWrapper = vk.DeviceWrapper
(
    vk.DeviceCommandFlags
    {

    }
);
pub const LayerInstanceWrapper = vk.InstanceWrapper
(
    vk.InstanceCommandFlags
    {
        .destroyInstance = true,
        .enumerateDeviceExtensionProperties = true,
        .getInstanceProcAddr = true,
        .getPhysicalDeviceMemoryProperties = true,
        .getPhysicalDeviceQueueFamilyProperties = true,
    }
);

pub const FramebufferBacking = std.BoundedArray(vk.Framebuffer, 256);
pub const ImageBacking = std.BoundedArray(vk.Image, 256);
pub const ImageViewBacking = std.BoundedArray(vk.ImageView, 256);
pub const PipelineStageFlagsBacking = std.BoundedArray(vk.PipelineStageFlags, 256);
pub const QueueDataBacking = std.BoundedArray(QueueData, 256);
pub const QueueFamilyPropsBacking = std.BoundedArray(vk.QueueFamilyProperties, 256);


pub var command_pool: vk.CommandPool = std.mem.zeroes(vk.CommandPool);
pub var current_image_count: u32 = 0;
pub var descriptor_layout: ?vk.DescriptorSetLayout = null;
pub var descriptor_pool: vk.DescriptorPool = std.mem.zeroes(vk.DescriptorPool);
pub var descriptor_set: ?vk.DescriptorSet = null;
pub var device_queues: QueueDataBacking = QueueDataBacking.init(0) catch @panic("oom");
pub var font_already_uploaded: bool = false;
pub var font_image_view: vk.ImageView = std.mem.zeroes(vk.ImageView);
pub var font_image: vk.Image = std.mem.zeroes(vk.Image);
pub var font_mem: vk.DeviceMemory = std.mem.zeroes(vk.DeviceMemory);
pub var font_sampler: ?vk.Sampler = null;
pub var format: ?vk.Format = null;
pub var framebuffers: FramebufferBacking = FramebufferBacking.init(0) catch @panic("oom");
pub var graphic_queue: ?*QueueData = null;
pub var height: ?u32 = null;
pub var image_views: ImageViewBacking = ImageViewBacking.init(0) catch @panic("oom");
pub var images: ImageBacking = ImageBacking.init(0) catch @panic("oom");
pub var persistent_device: ?vk.Device = null;
pub var physical_mem_props: ?vk.PhysicalDeviceMemoryProperties = null;
pub var pipeline_layout: vk.PipelineLayout = std.mem.zeroes(vk.PipelineLayout);
pub var pipeline: ?vk.Pipeline = null;
pub var previous_draw_data: ?DrawData = null;
pub var render_pass: vk.RenderPass = std.mem.zeroes(vk.RenderPass);
pub var swapchain: ?*vk.SwapchainKHR = null;
pub var upload_font_buffer_mem: vk.DeviceMemory = std.mem.zeroes(vk.DeviceMemory);
pub var upload_font_buffer: vk.Buffer = std.mem.zeroes(vk.Buffer);
pub var width: ?u32 = null;

pub var device_wrapper: ?LayerDeviceWrapper = null;
pub var instance_wrapper: ?LayerInstanceWrapper = null;
