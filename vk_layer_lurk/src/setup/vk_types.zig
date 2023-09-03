const std = @import("std");

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
        .allocateCommandBuffers = true,
        .allocateDescriptorSets = true,
        .allocateMemory = true,
        .beginCommandBuffer = true,
        .bindBufferMemory = true,
        .bindImageMemory = true,
        .cmdBeginRenderPass = true,
        .cmdBindDescriptorSets = true,
        .cmdBindIndexBuffer = true,
        .cmdBindPipeline = true,
        .cmdBindVertexBuffers = true,
        .cmdCopyBufferToImage = true,
        .cmdDraw = true,
        .cmdDrawIndexed = true,
        .cmdEndRenderPass = true,
        .cmdPipelineBarrier = true,
        .cmdPushConstants = true,
        .cmdSetScissor = true,
        .cmdSetViewport = true,
        .createBuffer = true,
        .createCommandPool = true,
        .createDescriptorPool = true,
        .createDescriptorSetLayout = true,
        .createFence = true,
        .createFramebuffer = true,
        .createGraphicsPipelines = true,
        .createImage = true,
        .createImageView = true,
        .createPipelineLayout = true,
        .createRenderPass = true,
        .createSampler = true,
        .createSemaphore = true,
        .createShaderModule = true,
        .createSwapchainKHR = true,
        .destroyBuffer = true,
        .destroyCommandPool = true,
        .destroyDescriptorPool = true,
        .destroyDescriptorSetLayout = true,
        .destroyDevice = true,
        .destroyFence = true,
        .destroyFramebuffer = true,
        .destroyImage = true,
        .destroyImageView = true,
        .destroyPipeline = true,
        .destroyPipelineLayout = true,
        .destroyRenderPass = true,
        .destroySampler = true,
        .destroySemaphore = true,
        .destroyShaderModule = true,
        .destroySwapchainKHR = true,
        .endCommandBuffer = true,
        .flushMappedMemoryRanges = true,
        .freeMemory = true,
        .getBufferMemoryRequirements = true,
        .getDeviceQueue = true,
        .getFenceStatus = true,
        .getImageMemoryRequirements = true,
        .getSwapchainImagesKHR = true,
        .mapMemory = true,
        .queuePresentKHR = true,
        .queueSubmit = true,
        .resetCommandBuffer = true,
        .resetFences = true,
        .unmapMemory = true,
        .updateDescriptorSets = true,
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
