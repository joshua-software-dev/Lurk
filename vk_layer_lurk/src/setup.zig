const std = @import("std");

const embedded_shaders = @import("embedded_shaders.zig");

const vk = @import("vk.zig");
const vk_layer_stubs = @import("vk_layer_stubs.zig");
const zgui = @import("zgui");


const QueueData = struct
{
    queue_family_index: u32,
    queue_flags: vk.QueueFlags,
    queue: vk.Queue,
    fence: vk.Fence,
};
const FramebufferBacking = std.BoundedArray(vk.Framebuffer, 256);
const ImageBacking = std.BoundedArray(vk.Image, 256);
const ImageViewBacking = std.BoundedArray(vk.ImageView, 256);
const QueueDataBacking = std.BoundedArray(QueueData, 256);
const QueueFamilyPropsBacking = std.BoundedArray(vk.QueueFamilyProperties, 256);

var descriptor_layout_container: [1]vk.DescriptorSetLayout = [1]vk.DescriptorSetLayout
{
    std.mem.zeroes(vk.DescriptorSetLayout),
};
var descriptor_layout: *vk.DescriptorSetLayout = &descriptor_layout_container[0];

var descriptor_set_container: [1]vk.DescriptorSet = [1]vk.DescriptorSet
{
    std.mem.zeroes(vk.DescriptorSet),
};
var descriptor_set: *vk.DescriptorSet = &descriptor_set_container[0];

var font_sampler_container: [1]vk.Sampler = [1]vk.Sampler
{
    std.mem.zeroes(vk.Sampler)
};
var font_sampler: *vk.Sampler = &font_sampler_container[0];

var pipeline_container: [1]vk.Pipeline = [1]vk.Pipeline
{
    std.mem.zeroes(vk.Pipeline),
};
var pipeline: *vk.Pipeline = &pipeline_container[0];

var command_pool: vk.CommandPool = std.mem.zeroes(vk.CommandPool);
var current_image_count: u32 = 0;
var current_imgui_context: ?zgui.Context = null;
var descriptor_pool: vk.DescriptorPool = std.mem.zeroes(vk.DescriptorPool);
var device_queues: QueueDataBacking = QueueDataBacking.init(0) catch @panic("oom");
var font_image_view: vk.ImageView = std.mem.zeroes(vk.ImageView);
var font_image: vk.Image = std.mem.zeroes(vk.Image);
var font_mem: vk.DeviceMemory = std.mem.zeroes(vk.DeviceMemory);
var format: ?vk.Format = null;
var framebuffers: FramebufferBacking = FramebufferBacking.init(0) catch @panic("oom");
var graphic_queue: ?*QueueData = null;
var height: ?u32 = null;
var image_views: ImageViewBacking = ImageViewBacking.init(0) catch @panic("oom");
var images: ImageBacking = ImageBacking.init(0) catch @panic("oom");
var physical_mem_props: ?vk.PhysicalDeviceMemoryProperties = null;
var pipeline_layout: vk.PipelineLayout = std.mem.zeroes(vk.PipelineLayout);
var render_pass: vk.RenderPass = std.mem.zeroes(vk.RenderPass);
var swapchain: ?*vk.SwapchainKHR = null;
var width: ?u32 = null;


fn vk_memory_type(properties: vk.MemoryPropertyFlags, type_bits: u32) u32
{
    if (physical_mem_props) |props|
    {
        var i: u32 = 0;
        var supported_mem_type: u32 = 1;
        while (i < props.memory_type_count) : ({i += 1; supported_mem_type += supported_mem_type;})
        {
            if
            (
                props.memory_types[i].property_flags.contains(properties)
                and ((type_bits & supported_mem_type) > 0)
            )
            {
                return i;
            }
        }

        @panic("Unable to find memory type");
    }

    @panic("Physical memory properties are null!");
}

fn setup_swapchain_data_pipeline(device: vk.Device, device_dispatcher: vk_layer_stubs.LayerDispatchTable) void
{
    // Create shader modules
    var frag_module: vk.ShaderModule = undefined;
    const frag_info = vk.ShaderModuleCreateInfo
    {
        .code_size = embedded_shaders.overlay_frag_spv.len * @sizeOf(u32),
        .p_code = embedded_shaders.overlay_frag_spv.ptr,
    };

    const frag_result = device_dispatcher.CreateShaderModule(device, &frag_info, null, &frag_module);
    if (frag_result != vk.Result.success)
    {
        @panic("Vulkan function call failed: Device.CreateShaderModule | frag shader");
    }

    var vert_module: vk.ShaderModule = undefined;
    const vert_info = vk.ShaderModuleCreateInfo
    {
        .code_size = embedded_shaders.overlay_vert_spv.len * @sizeOf(u32),
        .p_code = embedded_shaders.overlay_vert_spv.ptr,
    };

    const vert_result = device_dispatcher.CreateShaderModule(device, &vert_info, null, &vert_module);
    if (vert_result != vk.Result.success)
    {
        @panic("Vulkan function call failed: Device.CreateShaderModule | vert shader");
    }

    // Font sampler
    const font_sampler_info = std.mem.zeroInit
    (
        vk.SamplerCreateInfo,
        .{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_mode = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .min_lod = -1000,
            .max_lod = 1000,
            .max_anisotropy = 1,
        }
    );

    const font_sampler_result = device_dispatcher.CreateSampler(device, &font_sampler_info, null, font_sampler);
    if (font_sampler_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateSampler");

    // Descriptor pool
    const sampler_pool_size = [1]vk.DescriptorPoolSize
    {
        vk.DescriptorPoolSize
        {
            .type = .combined_image_sampler,
            .descriptor_count = 1,
        },
    };
    const desc_pool_info = vk.DescriptorPoolCreateInfo
    {
        .max_sets = 1,
        .pool_size_count = 1,
        .p_pool_sizes = &sampler_pool_size,
    };

    const desc_pool_result = device_dispatcher.CreateDescriptorPool(device, &desc_pool_info, null, &descriptor_pool);
    if (desc_pool_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateDescriptorPool");

    // Descriptor layout
    const binding = [1]vk.DescriptorSetLayoutBinding
    {
        std.mem.zeroInit
        (
            vk.DescriptorSetLayoutBinding,
            .{
                .descriptor_type = .combined_image_sampler,
                .descriptor_count = 1,
                .stage_flags = vk.ShaderStageFlags{ .fragment_bit = true, },
                .p_immutable_samplers = &font_sampler_container,
            }
        ),
    };
    const set_layout_info = vk.DescriptorSetLayoutCreateInfo
    {
        .binding_count = 1,
        .p_bindings = &binding,
    };

    const desc_layout_result = device_dispatcher.CreateDescriptorSetLayout
    (
        device,
        &set_layout_info,
        null,
        descriptor_layout
    );
    if (desc_layout_result != vk.Result.success)
    {
        @panic("Vulkan function call failed: Device.CreateDescriptorSetLayout");
    }

    // Descriptor set
    const alloc_info = vk.DescriptorSetAllocateInfo
    {
        .descriptor_pool = descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &descriptor_layout_container
    };

    const alloc_desc_set_result = device_dispatcher.AllocateDescriptorSets(device, &alloc_info, &descriptor_set_container);
    if (alloc_desc_set_result != vk.Result.success)
    {
        @panic("Vulkan function call failed: Device.AllocateDescriptorSets");
    }

    // Constants: we are using 'vec2 offset' and 'vec2 scale' instead of a full
    // 3d projection matrix
    const push_constants = [1]vk.PushConstantRange
    {
        vk.PushConstantRange
        {
            .stage_flags = vk.ShaderStageFlags{ .vertex_bit = true, },
            .offset = @sizeOf(f32) * 0, // can't this just be simplified to 0?
            .size = @sizeOf(f32) * 4,
        },
    };
    const layout_info = vk.PipelineLayoutCreateInfo
    {
        .set_layout_count = 1,
        .p_set_layouts = &descriptor_layout_container,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = &push_constants,
    };
    const create_pipeline_result = device_dispatcher.CreatePipelineLayout(device, &layout_info, null, &pipeline_layout);
    if (create_pipeline_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreatePipelineLayout");

    const stage = [2]vk.PipelineShaderStageCreateInfo
    {
        vk.PipelineShaderStageCreateInfo
        {
            .stage = vk.ShaderStageFlags{ .vertex_bit = true, },
            .module = vert_module,
            .p_name = "main",
        },
        vk.PipelineShaderStageCreateInfo
        {
            .stage = vk.ShaderStageFlags{ .fragment_bit = true, },
            .module = frag_module,
            .p_name = "main",
        },
    };

    const binding_desc = [1]vk.VertexInputBindingDescription
    {
        std.mem.zeroInit
        (
            vk.VertexInputBindingDescription,
            .{
                .input_rate = .vertex,
                .stride = @sizeOf(zgui.DrawVert),
            }
        ),
    };
    const attribute_desc = [3]vk.VertexInputAttributeDescription
    {
        vk.VertexInputAttributeDescription
        {
            .location = 0,
            .binding = binding_desc[0].binding,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(zgui.DrawVert, "pos"),
        },
        vk.VertexInputAttributeDescription
        {
            .location = 1,
            .binding = binding_desc[0].binding,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(zgui.DrawVert, "uv"),
        },
        vk.VertexInputAttributeDescription
        {
            .location = 2,
            .binding = binding_desc[0].binding,
            .format = .r8g8b8a8_unorm,
            .offset = @offsetOf(zgui.DrawVert, "color"),
        },
    };

    const vertex_info = vk.PipelineVertexInputStateCreateInfo
    {
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = &binding_desc,
        .vertex_attribute_description_count = 3,
        .p_vertex_attribute_descriptions = &attribute_desc,
    };

    const ia_info = std.mem.zeroInit
    (
        vk.PipelineInputAssemblyStateCreateInfo,
        .{
            .topology = .triangle_list,
        }
    );

    const viewport_info = vk.PipelineViewportStateCreateInfo
    {
        .viewport_count = 1,
        .scissor_count = 1,
    };

    const raster_info = std.mem.zeroInit
    (
        vk.PipelineRasterizationStateCreateInfo,
        .{
            .polygon_mode = .fill,
            .cull_mode = .{},
            .front_face = .counter_clockwise,
            .line_width = 1.0,
        }
    );

    const ms_info = std.mem.zeroInit
    (
        vk.PipelineMultisampleStateCreateInfo,
        .{
            .rasterization_samples = vk.SampleCountFlags{ .@"1_bit" = true, },
        }
    );

    const color_attachment = [1]vk.PipelineColorBlendAttachmentState
    {
        vk.PipelineColorBlendAttachmentState
        {
            .blend_enable = 1,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one_minus_src_alpha,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = vk.ColorComponentFlags
            {
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
                .a_bit = true,
            },
        },
    };

    const depth_info = std.mem.zeroInit(vk.PipelineDepthStencilStateCreateInfo, .{});

    const blend_info = std.mem.zeroInit
    (
        vk.PipelineColorBlendStateCreateInfo,
        .{
            .attachment_count = 1,
            .p_attachments = &color_attachment,
        }
    );

    const dynamic_states = [2]vk.DynamicState
    {
        .viewport,
        .scissor,
    };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo
    {
        .dynamic_state_count = @truncate(dynamic_states.len),
        .p_dynamic_states = &dynamic_states,
    };

    const info_container = [1]vk.GraphicsPipelineCreateInfo
    {
        std.mem.zeroInit
        (
            vk.GraphicsPipelineCreateInfo,
            .{
                .stage_count = 2,
                .p_stages = &stage,
                .p_vertex_input_state = &vertex_info,
                .p_input_assembly_state = &ia_info,
                .p_viewport_state = &viewport_info,
                .p_rasterization_state = &raster_info,
                .p_multisample_state = &ms_info,
                .p_depth_stencil_state = &depth_info,
                .p_color_blend_state = &blend_info,
                .p_dynamic_state = &dynamic_state,
                .layout = pipeline_layout,
                .render_pass = render_pass,
            }
        ),
    };
    const create_pl_result = device_dispatcher.CreateGraphicsPipelines
    (
        device,
        .null_handle,
        1,
        &info_container,
        null,
        &pipeline_container
    );
    if (create_pl_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateGraphicsPipelines");

    _ = device_dispatcher.DestroyShaderModule(device, vert_module, null);
    _ = device_dispatcher.DestroyShaderModule(device, frag_module, null);

    var h: i32 = 0;
    var w: i32 = 0;
    _ = zgui.io.getFontsTextDataAsRgba32(&h, &w);
    if (h < 1 or w < 1) @panic("ImGui provided an invalid font size.");

    // Font image
    const image_info = vk.ImageCreateInfo
    {
        .image_type = .@"2d",
        .format = .r8g8b8a8_unorm,
        .extent = .{ .depth = 1, .height = @intCast(h), .width = @intCast(w), },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = vk.SampleCountFlags{ .@"1_bit" = true, },
        .tiling = .optimal,
        .usage = vk.ImageUsageFlags{ .sampled_bit = true, .transfer_dst_bit = true, },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };
    const font_image_result = device_dispatcher.CreateImage(device, &image_info, null, &font_image);
    if (font_image_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateImage");

    var font_image_req: vk.MemoryRequirements = undefined;
    device_dispatcher.GetImageMemoryRequirements(device, font_image, &font_image_req);

    const image_alloc_info = vk.MemoryAllocateInfo
    {
        .allocation_size = font_image_req.size,
        .memory_type_index = vk_memory_type
        (
            vk.MemoryPropertyFlags{ .device_local_bit = true, },
            font_image_req.memory_type_bits
        ),
    };

    const alloc_mem_result = device_dispatcher.AllocateMemory(device, &image_alloc_info, null, &font_mem);
    if (alloc_mem_result != vk.Result.success) @panic("Vulkan function call failed: Device.AllocateMemory");

    const bind_image_result = device_dispatcher.BindImageMemory(device, font_image, font_mem, 0);
    if (bind_image_result != vk.Result.success) @panic("Vulkan function call failed: Device.BindImageMemory");

    // Font image view
    const view_info = std.mem.zeroInit
    (
        vk.ImageViewCreateInfo,
        .{
            .image = font_image,
            .view_type = .@"2d",
            .format = .r8g8b8a8_unorm,
            .subresource_range = std.mem.zeroInit
            (
                vk.ImageSubresourceRange,
                .{
                    .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
                    .level_count = 1,
                    .layer_count = 1,
                }
            )
        }
    );
    const create_view_result = device_dispatcher.CreateImageView(device, &view_info, null, &font_image_view);
    if (create_view_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateImageView");

    // Descriptor set
    const desc_image = [1]vk.DescriptorImageInfo
    {
        vk.DescriptorImageInfo
        {
            .sampler = font_sampler.*,
            .image_view = font_image_view,
            .image_layout = .shader_read_only_optimal,
        },
    };
    const write_desc = [1]vk.WriteDescriptorSet
    {
        std.mem.zeroInit
        (
            vk.WriteDescriptorSet,
            .{
                .dst_set = descriptor_set.*,
                .descriptor_count = 1,
                .descriptor_type = .combined_image_sampler,
                .p_image_info = &desc_image,
                .p_buffer_info = &[1]vk.DescriptorBufferInfo
                {
                    vk.DescriptorBufferInfo
                    {
                        .offset = 0,
                        .range = 0,
                    }
                },
                .p_texel_buffer_view = &[1]vk.BufferView
                {
                    vk.BufferView.null_handle,
                },
            }
        ),
    };
    device_dispatcher.UpdateDescriptorSets(device, 1, &write_desc, 0, null);
}

pub fn setup_swapchain
(
    device: vk.Device,
    device_dispatcher: vk_layer_stubs.LayerDispatchTable,
    p_create_info: *const vk.SwapchainCreateInfoKHR,
    p_swapchain: *vk.SwapchainKHR
)
void
{
    swapchain = p_swapchain;

    height = p_create_info.image_extent.height;
    width = p_create_info.image_extent.width;
    format = p_create_info.image_format;

    current_imgui_context = zgui.zguiCreateContext(null);
    zgui.zguiSetCurrentContext(current_imgui_context);

    zgui.io.setIniFilename(null);
    zgui.io.setDisplaySize(@floatFromInt(width.?), @floatFromInt(height.?));

    const attachment_desc = [1]vk.AttachmentDescription
    {
        vk.AttachmentDescription
        {
            .format = format.?,
            .samples = vk.SampleCountFlags{ .@"1_bit" = true, },
            .load_op = .load,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .color_attachment_optimal,
            .final_layout = .present_src_khr,
        },
    };

    const color_attachment = [1]vk.AttachmentReference
    {
        vk.AttachmentReference
        {
            .attachment = 0,
            .layout = .color_attachment_optimal,
        },
    };

    const subpass = [1]vk.SubpassDescription
    {
        vk.SubpassDescription
        {
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &color_attachment,
        },
    };

    const dependency = [1]vk.SubpassDependency
    {
        vk.SubpassDependency
        {
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true, },
            .dst_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true, },
            .src_access_mask = .{},
            .dst_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true, },
        },
    };

    const render_pass_info = vk.RenderPassCreateInfo
    {
        .s_type = .render_pass_create_info,
        .attachment_count = 1,
        .p_attachments = &attachment_desc,
        .subpass_count = 1,
        .p_subpasses = &subpass,
        .dependency_count = 1,
        .p_dependencies = &dependency,
    };

    const create_rp_result = device_dispatcher.CreateRenderPass(device, &render_pass_info, null, &render_pass);
    if (create_rp_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateRenderPass");

    setup_swapchain_data_pipeline(device, device_dispatcher);

    const get_img_result1 = device_dispatcher.GetSwapchainImagesKHR(device, swapchain.?.*, &current_image_count, null);
    if (get_img_result1 != vk.Result.success) @panic("Vulkan function call failed: Device.GetSwapchainImagesKHR");

    framebuffers.resize(current_image_count) catch @panic("Framebuffer buffer overflow");
    image_views.resize(current_image_count) catch @panic("Image View buffer overflow");
    images.resize(current_image_count) catch @panic("Image buffer overflow");

    const get_img_result2 = device_dispatcher.GetSwapchainImagesKHR
    (
        device,
        swapchain.?.*,
        &current_image_count,
        &images.buffer
    );
    if (get_img_result2 != vk.Result.success) @panic("Vulkan function call failed: Device.GetSwapchainImagesKHR");

    // Image views
    var view_info = std.mem.zeroInit
    (
        vk.ImageViewCreateInfo,
        .{
            .view_type = .@"2d",
            .format = format.?,
            .components = vk.ComponentMapping
            {
                .r = .r,
                .g = .g,
                .b = .b,
                .a = .a,
            },
            .subresource_range = vk.ImageSubresourceRange
            {
                .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }
    );

    {
        var i: u32 = 0;
        while (i < current_image_count) : (i += 1)
        {
            view_info.image = images.buffer[i];
            const create_imgv_result = device_dispatcher.CreateImageView(device, &view_info, null, &image_views.buffer[i]);
            if (create_imgv_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateImageView");
        }
    }

    // Framebuffers
    var fb_info = vk.FramebufferCreateInfo
    {
        .render_pass = render_pass,
        .attachment_count = 1,
        .width = width.?,
        .height = height.?,
        .layers = 1,
    };

    {
        var i: u32 = 0;
        while (i < current_image_count) : (i += 1)
        {
            fb_info.p_attachments = image_views.buffer[i..i].ptr;
            const create_fb_result = device_dispatcher.CreateFramebuffer(device, &fb_info, null, &framebuffers.buffer[i]);
            if (create_fb_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateFramebuffer");
        }
    }

    // Command buffer pool
    const cmd_buffer_pool_info = vk.CommandPoolCreateInfo
    {
        .flags = vk.CommandPoolCreateFlags{ .reset_command_buffer_bit = true, },
        .queue_family_index = (graphic_queue orelse @panic("graphics QueueData was null")).queue_family_index,
    };
    const create_pool_result = device_dispatcher.CreateCommandPool(device, &cmd_buffer_pool_info, null, &command_pool);
    if (create_pool_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateCommandPool");
}

pub fn destroy_swapchain(device: vk.Device, device_dispatcher: vk_layer_stubs.LayerDispatchTable) void
{
    std.log.scoped(.LAYER).debug("Destroying render pass...", .{});
    device_dispatcher.DestroyRenderPass(device, render_pass, null);
}

pub fn destroy_instance(instance: vk.Instance, instance_dispatcher: ?vk_layer_stubs.LayerInstanceDispatchTable) void
{
    _ = instance;
    _ = instance_dispatcher;
    zgui.zguiDestroyContext(current_imgui_context);
}

pub fn get_physical_mem_props
(
    physical_device: vk.PhysicalDevice,
    instance_dispatcher: vk_layer_stubs.LayerInstanceDispatchTable,
)
void
{
    physical_mem_props = undefined;
    instance_dispatcher.GetPhysicalDeviceMemoryProperties(physical_device, &physical_mem_props.?);
}

fn new_queue_data
(
    data: *QueueData,
    device: vk.Device,
    device_dispatcher: vk_layer_stubs.LayerDispatchTable,
)
void
{
    // Fence synchronizing access to queries on that queue.
    const fence_info = vk.FenceCreateInfo
    {
        .flags = vk.FenceCreateFlags{ .signaled_bit = true, },
    };
    const create_fence_result = device_dispatcher.CreateFence(device, &fence_info, null, &data.fence);
    if (create_fence_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateFence");

    if (vk.QueueFlags.contains(data.queue_flags, vk.QueueFlags{ .graphics_bit = true,}))
    {
        graphic_queue = data;
    }
}

pub fn device_map_queues
(
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    device_dispatcher: vk_layer_stubs.LayerDispatchTable,
    instance_dispatcher: vk_layer_stubs.LayerInstanceDispatchTable,
    layer_dispatcher: vk_layer_stubs.LayerInitDispatchTable,
    p_create_info: *const vk.DeviceCreateInfo,
)
void
{
    var queue_family_props_count: u32 = 0;
    instance_dispatcher.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_props_count, null);

    var family_props = QueueFamilyPropsBacking.init(0)
    catch @panic("Failed to get backing buffer for QueueFamilyProperties");
    family_props.resize(queue_family_props_count) catch @panic("QueueFamilyProperties buffer overflow");

    instance_dispatcher.GetPhysicalDeviceQueueFamilyProperties
    (
        physical_device,
        &queue_family_props_count,
        &family_props.buffer,
    );

    var device_queue_index: u32 = 0;
    var i: u32 = 0;
    while (i < p_create_info.queue_create_info_count) : (i += 1)
    {
        const queue_family_index = p_create_info.p_queue_create_infos[i].queue_family_index;
        var j: u32 = 0;
        while (j < p_create_info.p_queue_create_infos[i].queue_count) : ({j += 1; device_queue_index += 1;})
        {
            device_queues.resize(device_queue_index + 1) catch @panic("QueueDataBacking buffer overflow");
            var data: *QueueData = &device_queues.buffer[device_queue_index];
            data.* = std.mem.zeroInit
            (
                QueueData,
                .{
                    .queue_family_index = queue_family_index,
                    .queue_flags = family_props.buffer[queue_family_index].queue_flags,
                }
            );

            device_dispatcher.GetDeviceQueue
            (
                device,
                queue_family_index,
                j,
                &data.queue
            );

            const set_dvc_loader_result = layer_dispatcher.pfn_set_device_loader_data(device, &data.queue);
            if (set_dvc_loader_result != vk.Result.success)
            {
                @panic("Vulkan function call failed: Stubs.PfnSetDeviceLoaderData");
            }

            new_queue_data(data, device, device_dispatcher);
        }
    }
}
