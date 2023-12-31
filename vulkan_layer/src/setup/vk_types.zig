const std = @import("std");

const overlay_gui = @import("overlay_gui");
const vkl = @import("vk_layer_stubs.zig");

const vk = @import("vk");


pub const DeviceData = struct
{
    device_id: u32,
    device: vk.Device,
    physical_device: vk.PhysicalDevice,
    get_device_proc_addr_func: vk.PfnGetDeviceProcAddr,
    set_device_loader_data_func: vkl.PfnSetDeviceLoaderData,
    graphic_queue: ?*VkQueueData,
    queues: VkQueueDataBacking,
    previous_draw_data: ?DrawData,
    device_wrapper: LayerDeviceWrapper,
};
pub const DrawData = struct
{
    command_buffer: vk.CommandBuffer = .null_handle,

    cross_engine_semaphore: vk.Semaphore = .null_handle,

    semaphore: vk.Semaphore = .null_handle,
    fence: vk.Fence = .null_handle,

    vertex_buffer: vk.Buffer = .null_handle,
    vertex_buffer_mem: vk.DeviceMemory = .null_handle,
    vertex_buffer_size: vk.DeviceSize = 0,

    index_buffer: vk.Buffer = .null_handle,
    index_buffer_mem: vk.DeviceMemory = .null_handle,
    index_buffer_size: vk.DeviceSize = 0,
};
pub const InstanceData = struct
{
    instance_id: u32,
    instance: vk.Instance,
    get_inst_proc_addr_func_ptr: vk.PfnGetInstanceProcAddr,
    instance_wrapper: LayerInstanceWrapper,
    physical_devices: PhysicalDeviceBacking,
};
pub const SwapchainData = struct
{
    swapchain_id: u32,
    command_pool: ?vk.CommandPool,
    descriptor_layout: ?vk.DescriptorSetLayout,
    descriptor_pool: ?vk.DescriptorPool,
    descriptor_set: ?vk.DescriptorSet,
    device: vk.Device,
    font_image_view: ?vk.ImageView,
    font_image: ?vk.Image,
    font_mem: ?vk.DeviceMemory,
    font_sampler: ?vk.Sampler,
    font_uploaded: bool,
    format: ?vk.Format,
    height: ?u32,
    image_count: ?u32,
    pipeline_layout: ?vk.PipelineLayout,
    pipeline: ?vk.Pipeline,
    render_pass: ?vk.RenderPass,
    swapchain: ?vk.SwapchainKHR,
    upload_font_buffer_mem: ?vk.DeviceMemory,
    upload_font_buffer: ?vk.Buffer,
    width: ?u32,
    framebuffers: FramebufferBacking,
    image_views: ImageViewBacking,
    images: ImageBacking,
};
pub const VkQueueData = struct
{
    device: vk.Device,
    queue_family_index: u32,
    queue_flags: vk.QueueFlags,
    queue: vk.Queue,
    fence: vk.Fence,
};

pub const LayerDeviceWrapper = vk.DeviceWrapper
(
    .{
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
    .{
        .destroyInstance = true,
        .enumerateDeviceExtensionProperties = true,
        .enumeratePhysicalDevices = true,
        .getPhysicalDeviceMemoryProperties = true,
        .getPhysicalDeviceQueueFamilyProperties = true,
    },
);

pub const FramebufferBacking = std.BoundedArray(vk.Framebuffer, 32);
pub const ImageBacking = std.BoundedArray(vk.Image, 32);
pub const ImageViewBacking = std.BoundedArray(vk.ImageView, 32);
pub const PipelineStageFlagsBacking = std.BoundedArray(vk.PipelineStageFlags, 32);
pub const PhysicalDeviceBacking = std.BoundedArray(vk.PhysicalDevice, 8);
pub const VkQueueDataBacking = std.BoundedArray(VkQueueData, 8);
pub const VkQueueFamilyPropsBacking = std.BoundedArray(vk.QueueFamilyProperties, 256);

pub const DeviceDataHashMap = std.hash_map.HashMap
(
    vk.Device,
    DeviceData,
    std.hash_map.AutoContext(vk.Device),
    99,
);
pub const InstanceDataHashMap = std.hash_map.HashMap
(
    vk.Instance,
    InstanceData,
    std.hash_map.AutoContext(vk.Instance),
    99,
);
pub const SwapchainDataHashMap = std.hash_map.HashMap
(
    vk.SwapchainKHR,
    SwapchainData,
    std.hash_map.AutoContext(vk.SwapchainKHR),
    99,
);
pub const PhyDevToInstanceHashMap = std.hash_map.HashMap
(
    vk.PhysicalDevice,
    vk.Instance,
    std.hash_map.AutoContext(vk.PhysicalDevice),
    99,
);
pub const VkQueueDataHashMap = std.hash_map.HashMap
(
    vk.Queue,
    VkQueueData,
    std.hash_map.AutoContext(vk.Queue),
    99,
);
