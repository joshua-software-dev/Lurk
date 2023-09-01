const std = @import("std");

const vk_layer_stubs = @import("vk_layer_stubs.zig");

const vk = @import("../vk.zig");


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

pub const LayerBaseWrapper = vk.BaseWrapper
(
    vk.BaseCommandFlags
    {
        .createInstance = true,
        .getInstanceProcAddr = true,
    },
);
pub const LayerDeviceWrapper = vk.DeviceWrapper
(
    vk.DeviceCommandFlags
    {
        // dispatch_table.AllocateCommandBuffers,
        .allocateCommandBuffers = true,
        // dispatch_table.AllocateDescriptorSets,
        .allocateDescriptorSets = true,
        // dispatch_table.AllocateMemory,
        .allocateMemory = true,
        // dispatch_table.BeginCommandBuffer,
        .beginCommandBuffer = true,
        // dispatch_table.BindBufferMemory,
        .bindBufferMemory = true,
        // dispatch_table.BindImageMemory,
        .bindImageMemory = true,
        // dispatch_table.CmdBeginRenderPass,
        .cmdBeginRenderPass = true,
        // dispatch_table.CmdBindDescriptorSets,
        .cmdBindDescriptorSets = true,
        // dispatch_table.CmdBindIndexBuffer,
        .cmdBindIndexBuffer = true,
        // dispatch_table.CmdBindPipeline,
        .cmdBindPipeline = true,
        // dispatch_table.CmdBindVertexBuffers,
        .cmdBindVertexBuffers = true,
        // dispatch_table.CmdCopyBufferToImage,
        .cmdCopyBufferToImage = true,
        // dispatch_table.CmdDraw,
        .cmdDraw = true,
        // dispatch_table.CmdDrawIndexed,
        .cmdDrawIndexed = true,
        // dispatch_table.CmdEndRenderPass,
        .cmdEndRenderPass = true,
        // dispatch_table.CmdPipelineBarrier,
        .cmdPipelineBarrier = true,
        // dispatch_table.CmdPushConstants,
        .cmdPushConstants = true,
        // dispatch_table.CmdSetScissor,
        .cmdSetScissor = true,
        // dispatch_table.CmdSetViewport,
        .cmdSetViewport = true,
        // dispatch_table.CreateBuffer,
        .createBuffer = true,
        // dispatch_table.CreateCommandPool,
        .createCommandPool = true,
        // dispatch_table.CreateDescriptorPool,
        .createDescriptorPool = true,
        // dispatch_table.CreateDescriptorSetLayout,
        .createDescriptorSetLayout = true,
        // dispatch_table.CreateFence,
        .createFence = true,
        // dispatch_table.CreateFramebuffer,
        .createFramebuffer = true,
        // dispatch_table.CreateGraphicsPipelines,
        .createGraphicsPipelines = true,
        // dispatch_table.CreateImage,
        .createImage = true,
        // dispatch_table.CreateImageView,
        .createImageView = true,
        // dispatch_table.CreatePipelineLayout,
        .createPipelineLayout = true,
        // dispatch_table.CreateRenderPass,
        .createRenderPass = true,
        // dispatch_table.CreateSampler,
        .createSampler = true,
        // dispatch_table.CreateSemaphore,
        .createSemaphore = true,
        // dispatch_table.CreateShaderModule,
        .createShaderModule = true,
        // dispatch_table.CreateSwapchainKHR,
        .createSwapchainKHR = true,
        // dispatch_table.DestroyBuffer,
        .destroyBuffer = true,
        // dispatch_table.DestroyDevice,
        .destroyDevice = true,
        // dispatch_table.DestroyRenderPass,
        .destroyRenderPass = true,
        // dispatch_table.DestroyShaderModule,
        .destroyShaderModule = true,
        // dispatch_table.DestroySwapchainKHR,
        .destroySwapchainKHR = true,
        // dispatch_table.EndCommandBuffer,
        .endCommandBuffer = true,
        // dispatch_table.FlushMappedMemoryRanges,
        .flushMappedMemoryRanges = true,
        // dispatch_table.FreeMemory,
        .freeMemory = true,
        // dispatch_table.GetBufferMemoryRequirements,
        .getBufferMemoryRequirements = true,
        // dispatch_table.GetDeviceProcAddr,
        // .getDeviceProcAddr = true,
        // dispatch_table.GetDeviceQueue,
        .getDeviceQueue = true,
        // dispatch_table.GetFenceStatus,
        .getFenceStatus = true,
        // dispatch_table.GetImageMemoryRequirements,
        .getImageMemoryRequirements = true,
        // dispatch_table.GetSwapchainImagesKHR,
        .getSwapchainImagesKHR = true,
        // dispatch_table.MapMemory,
        .mapMemory = true,
        // dispatch_table.QueuePresentKHR,
        .queuePresentKHR = true,
        // dispatch_table.QueueSubmit,
        .queueSubmit = true,
        // dispatch_table.ResetCommandBuffer,
        .resetCommandBuffer = true,
        // dispatch_table.ResetFences,
        .resetFences = true,
        // dispatch_table.UnmapMemory,
        .unmapMemory = true,
        // dispatch_table.UpdateDescriptorSets,
        .updateDescriptorSets = true,
        // dispatch_table.WaitForFences,
        .waitForFences = true,
    },
);
pub const LayerInstanceWrapper = vk.InstanceWrapper
(
    vk.InstanceCommandFlags
    {
        .createDevice = true,
        .destroyInstance = true,
        .enumerateDeviceExtensionProperties = true,
        .getPhysicalDeviceMemoryProperties = true,
        .getPhysicalDeviceQueueFamilyProperties = true,
    },
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

// single global lock, for simplicity
pub var wrappers_global_lock: std.Thread.Mutex = .{};
pub var base_wrapper: ?LayerBaseWrapper = null;
pub var device_wrapper: ?LayerDeviceWrapper = null;
pub var init_wrapper: ?vk_layer_stubs.LayerInitWrapper = null;
pub var instance_wrapper: ?LayerInstanceWrapper = null;
