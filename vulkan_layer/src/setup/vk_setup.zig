const std = @import("std");

const overlay_gui = @import("overlay_gui");
const shaders = @import("../shaders/vk_shaders.zig");
const vkh = @import("vk_helpers.zig");
const vkl = @import("vk_layer_stubs.zig");
const vkt = @import("vk_types.zig");

const vk = @import("vk");


fn setup_swapchain_data_pipeline
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    swapchain_data: *vkt.SwapchainData,
)
void
{
    // Create shader modules
    const frag_info: vk.ShaderModuleCreateInfo = .{
        .code_size = shaders.overlay_frag_spv.len * @sizeOf(u32),
        .p_code = shaders.overlay_frag_spv.ptr,
    };
    const frag_module = device_wrapper.createShaderModule(device, &frag_info, null)
        catch @panic("Vulkan function call failed: Device.CreateShaderModule | frag shader");

    const vert_info: vk.ShaderModuleCreateInfo = .{
        .code_size = shaders.overlay_vert_spv.len * @sizeOf(u32),
        .p_code = shaders.overlay_vert_spv.ptr,
    };
    const vert_module = device_wrapper.createShaderModule(device, &vert_info, null)
        catch @panic("Vulkan function call failed: Device.CreateShaderModule | vert shader");

    // Font sampler
    const font_sampler_info: vk.SamplerCreateInfo = .{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .min_lod = -1000,
        .max_lod = 1000,
        .max_anisotropy = 1,
        // zero init
        .anisotropy_enable = 0,
        .border_color = .float_transparent_black,
        .compare_enable = 0,
        .compare_op = .never,
        .mip_lod_bias = 0,
        .unnormalized_coordinates = 0,
    };

    swapchain_data.font_sampler = device_wrapper.createSampler(device, &font_sampler_info, null)
        catch @panic("Vulkan function call failed: Device.CreateSampler");

    // Descriptor pool
    const sampler_pool_size: [1]vk.DescriptorPoolSize = .{
        .{
            .type = .combined_image_sampler,
            .descriptor_count = 1,
        },
    };
    const desc_pool_info: vk.DescriptorPoolCreateInfo = .{
        .max_sets = 1,
        .pool_size_count = 1,
        .p_pool_sizes = &sampler_pool_size,
    };

    swapchain_data.descriptor_pool = device_wrapper.createDescriptorPool(device, &desc_pool_info, null)
        catch @panic("Vulkan function call failed: Device.CreateDescriptorPool");

    // Descriptor layout
    const binding: [1]vk.DescriptorSetLayoutBinding = .{
        .{
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = vk.ShaderStageFlags{ .fragment_bit = true, },
            .p_immutable_samplers = &@as([1]vk.Sampler, .{ swapchain_data.font_sampler.?, }),
            // zero init
            .binding = 0,
        },
    };
    const set_layout_info: vk.DescriptorSetLayoutCreateInfo = .{
        .binding_count = 1,
        .p_bindings = &binding,
    };
    swapchain_data.descriptor_layout = device_wrapper.createDescriptorSetLayout(device, &set_layout_info, null)
        catch @panic("Vulkan function call failed: Device.CreateDescriptorSetLayout");

    // Descriptor set
    const alloc_info: vk.DescriptorSetAllocateInfo = .{
        .descriptor_pool = swapchain_data.descriptor_pool.?,
        .descriptor_set_count = 1,
        .p_set_layouts = &@as([1]vk.DescriptorSetLayout, .{ swapchain_data.descriptor_layout.?, }),
    };

    var descriptor_set_container: [1]vk.DescriptorSet = .{ vk.DescriptorSet.null_handle, };
    device_wrapper.allocateDescriptorSets(device, &alloc_info, &descriptor_set_container)
        catch @panic("Vulkan function call failed: Device.AllocateDescriptorSets");
    swapchain_data.descriptor_set = descriptor_set_container[0];

    // Constants: we are using 'vec2 offset' and 'vec2 scale' instead of a full
    // 3d projection matrix
    const push_constants: [1]vk.PushConstantRange = .{
        .{
            .stage_flags = .{ .vertex_bit = true, },
            .offset = @sizeOf(f32) * 0, // can't this just be simplified to 0?
            .size = @sizeOf(f32) * 4,
        },
    };
    const layout_info: vk.PipelineLayoutCreateInfo = .{
        .set_layout_count = 1,
        .p_set_layouts = &@as([1]vk.DescriptorSetLayout, .{ swapchain_data.descriptor_layout.?, }),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = &push_constants,
    };
    swapchain_data.pipeline_layout = device_wrapper.createPipelineLayout(device, &layout_info, null)
        catch @panic("Vulkan function call failed: Device.CreatePipelineLayout");

    const stage: [2]vk.PipelineShaderStageCreateInfo = .{
        .{
            .stage = .{ .vertex_bit = true, },
            .module = vert_module,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true, },
            .module = frag_module,
            .p_name = "main",
        },
    };

    const binding_desc: [1]vk.VertexInputBindingDescription = .{
        .{
            .input_rate = .vertex,
            .stride = @sizeOf(overlay_gui.DrawVert),
            // zero init
            .binding = 0,
        }
    };
    const attribute_desc: [3]vk.VertexInputAttributeDescription = .{
        .{
            .location = 0,
            .binding = binding_desc[0].binding,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(overlay_gui.DrawVert, "pos"),
        },
        .{
            .location = 1,
            .binding = binding_desc[0].binding,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(overlay_gui.DrawVert, "uv"),
        },
        .{
            .location = 2,
            .binding = binding_desc[0].binding,
            .format = .r8g8b8a8_unorm,
            .offset = @offsetOf(overlay_gui.DrawVert, "col"),
        },
    };

    const vertex_info: vk.PipelineVertexInputStateCreateInfo = .{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = &binding_desc,
        .vertex_attribute_description_count = 3,
        .p_vertex_attribute_descriptions = &attribute_desc,
    };

    const ia_info: vk.PipelineInputAssemblyStateCreateInfo = .{
        .topology = .triangle_list,
        // zero init
        .primitive_restart_enable = 0,
    };

    const viewport_info: vk.PipelineViewportStateCreateInfo = .
    {
        .viewport_count = 1,
        .scissor_count = 1,
    };

    const raster_info: vk.PipelineRasterizationStateCreateInfo = .{
        .polygon_mode = .fill,
        .cull_mode = .{},
        .front_face = .counter_clockwise,
        .line_width = 1.0,
        // zero init
        .depth_bias_clamp = 0,
        .depth_bias_constant_factor = 0,
        .depth_bias_enable = 0,
        .depth_bias_slope_factor = 0,
        .depth_clamp_enable = 0,
        .rasterizer_discard_enable = 0,
    };

    const ms_info: vk.PipelineMultisampleStateCreateInfo = .{
        .rasterization_samples = .{ .@"1_bit" = true, },
        // zero init
        .alpha_to_coverage_enable = 0,
        .alpha_to_one_enable = 0,
        .min_sample_shading = 0,
        .sample_shading_enable = 0,
    };

    const color_attachment: [1]vk.PipelineColorBlendAttachmentState = .{
        .{
            .blend_enable = 1,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one_minus_src_alpha,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
                .a_bit = true,
            },
        },
    };

    const depth_info: vk.PipelineDepthStencilStateCreateInfo = .{
        // zero init
        .back = .{
            .compare_mask = 0,
            .compare_op = .never,
            .depth_fail_op = .keep,
            .fail_op = .keep,
            .pass_op = .keep,
            .reference = 0,
            .write_mask = 0,
        },
        .depth_bounds_test_enable = 0,
        .depth_compare_op = .never,
        .depth_test_enable = 0,
        .depth_write_enable = 0,
        .front = .{
            .compare_mask = 0,
            .compare_op = .never,
            .depth_fail_op = .keep,
            .fail_op = .keep,
            .pass_op = .keep,
            .reference = 0,
            .write_mask = 0,
        },
        .min_depth_bounds = 0,
        .stencil_test_enable = 0,
        .max_depth_bounds = 0,
    };

    const blend_info: vk.PipelineColorBlendStateCreateInfo = .{
        .attachment_count = 1,
        .p_attachments = &color_attachment,
        // zero init
        .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
        .logic_op = .clear,
        .logic_op_enable = 0,
    };

    const dynamic_states: [2]vk.DynamicState = .{
        .viewport,
        .scissor,
    };
    const dynamic_state: vk.PipelineDynamicStateCreateInfo = .{
        .dynamic_state_count = @truncate(dynamic_states.len),
        .p_dynamic_states = &dynamic_states,
    };

    const info_container: [1]vk.GraphicsPipelineCreateInfo = .{
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
            .layout = swapchain_data.pipeline_layout.?,
            .render_pass = swapchain_data.render_pass.?,
            // zero init
            .base_pipeline_index = 0,
            .subpass = 0,
        },
    };
    var pipeline_container: [1]vk.Pipeline = .{ vk.Pipeline.null_handle, };
    _ = device_wrapper.createGraphicsPipelines(device, .null_handle, 1, &info_container, null, &pipeline_container)
        catch @panic("Vulkan function call failed: Device.CreateGraphicsPipelines");
    swapchain_data.pipeline = pipeline_container[0];

    device_wrapper.destroyShaderModule(device, vert_module, null);
    device_wrapper.destroyShaderModule(device, frag_module, null);

    var h: i32 = 0;
    var w: i32 = 0;
    _ = overlay_gui.setup_font_text_data(&w, &h)
        catch @panic("ImGui provided an invalid font size.");

    // Font image
    const image_info: vk.ImageCreateInfo = .{
        .image_type = .@"2d",
        .format = .r8g8b8a8_unorm,
        .extent = .{ .depth = 1, .height = @intCast(h), .width = @intCast(w), },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true, },
        .tiling = .optimal,
        .usage = .{ .sampled_bit = true, .transfer_dst_bit = true, },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };
    swapchain_data.font_image = device_wrapper.createImage(device, &image_info, null)
        catch @panic("Vulkan function call failed: Device.CreateImage");

    var font_image_req = device_wrapper.getImageMemoryRequirements(device, swapchain_data.font_image.?);

    const image_alloc_info: vk.MemoryAllocateInfo = .{
        .allocation_size = font_image_req.size,
        .memory_type_index = vkh.vk_memory_type
        (
            device,
            .{ .device_local_bit = true, },
            font_image_req.memory_type_bits
        ),
    };
    swapchain_data.font_mem = device_wrapper.allocateMemory(device, &image_alloc_info, null)
        catch @panic("Vulkan function call failed: Device.AllocateMemory");

    device_wrapper.bindImageMemory(device, swapchain_data.font_image.?, swapchain_data.font_mem.?, 0)
        catch @panic("Vulkan function call failed: Device.BindImageMemory");

    // Font image view
    const view_info: vk.ImageViewCreateInfo = .{
        .image = swapchain_data.font_image.?,
        .view_type = .@"2d",
        .format = .r8g8b8a8_unorm,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true, },
            .level_count = 1,
            .layer_count = 1,
            // zero init
            .base_array_layer = 0,
            .base_mip_level = 0,
        },
        // zero init
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        }
    };
    swapchain_data.font_image_view = device_wrapper.createImageView(device, &view_info, null)
        catch @panic("Vulkan function call failed: Device.CreateImageView");

    // Descriptor set
    const desc_image: [1]vk.DescriptorImageInfo = .{
        .{
            .sampler = swapchain_data.font_sampler.?,
            .image_view = swapchain_data.font_image_view.?,
            .image_layout = .shader_read_only_optimal,
        },
    };
    const write_desc: [1]vk.WriteDescriptorSet = .{
        .{
            .dst_set = swapchain_data.descriptor_set.?,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &desc_image,
            .p_buffer_info = &@as([1]vk.DescriptorBufferInfo, .{ .{ .offset = 0, .range = 0, } }),
            .p_texel_buffer_view = &@as([1]vk.BufferView, .{ vk.BufferView.null_handle, }),
            // zero init
            .dst_array_element = 0,
            .dst_binding = 0,
        },
    };
    device_wrapper.updateDescriptorSets(device, 1, &write_desc, 0, null);
}

pub fn setup_swapchain
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    p_create_info: *const vk.SwapchainCreateInfoKHR,
    swapchain_data: *vkt.SwapchainData,
    g_graphic_queue: *const vkt.VkQueueData,
)
void
{
    swapchain_data.height = p_create_info.image_extent.height;
    swapchain_data.width = p_create_info.image_extent.width;
    swapchain_data.format = p_create_info.image_format;

    overlay_gui.create_overlay_context
    (
        @floatFromInt(swapchain_data.width.?),
        @floatFromInt(swapchain_data.height.?),
    );

    const old_ctx = overlay_gui.use_overlay_context()
        catch unreachable;
    defer overlay_gui.restore_old_context(old_ctx);

    const attachment_desc: [1]vk.AttachmentDescription = .{
        .{
            .format = swapchain_data.format.?,
            .samples = .{ .@"1_bit" = true, },
            .load_op = .load,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .color_attachment_optimal,
            .final_layout = .present_src_khr,
        },
    };

    const color_attachment: [1]vk.AttachmentReference = .{
        .{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        },
    };

    const subpass: [1]vk.SubpassDescription = .{
        .{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &color_attachment,
        },
    };

    const dependency: [1]vk.SubpassDependency = .{
        .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true, },
            .dst_stage_mask = .{ .color_attachment_output_bit = true, },
            .src_access_mask = .{},
            .dst_access_mask = .{ .color_attachment_write_bit = true, },
        },
    };

    const render_pass_info: vk.RenderPassCreateInfo = .{
        .s_type = .render_pass_create_info,
        .attachment_count = 1,
        .p_attachments = &attachment_desc,
        .subpass_count = 1,
        .p_subpasses = &subpass,
        .dependency_count = 1,
        .p_dependencies = &dependency,
    };

    swapchain_data.render_pass = device_wrapper.createRenderPass(device, &render_pass_info, null)
        catch @panic("Vulkan function call failed: Device.CreateRenderPass");

    setup_swapchain_data_pipeline
    (
        device,
        device_wrapper,
        swapchain_data,
    );

    swapchain_data.image_count = 0;
    _ = device_wrapper.getSwapchainImagesKHR
    (
        device,
        swapchain_data.swapchain.?,
        &swapchain_data.image_count.?,
        null,
    )
        catch @panic("Vulkan function call failed: Device.GetSwapchainImagesKHR 1");

    swapchain_data.framebuffers.resize(swapchain_data.image_count.?)
        catch @panic("Framebuffer buffer overflow");
    swapchain_data.image_views.resize(swapchain_data.image_count.?)
        catch @panic("Image View buffer overflow");
    swapchain_data.images.resize(swapchain_data.image_count.?)
        catch @panic("Image buffer overflow");

    _ = device_wrapper.getSwapchainImagesKHR
    (
        device,
        swapchain_data.swapchain.?,
        &swapchain_data.image_count.?,
        swapchain_data.images.slice().ptr,
    )
        catch @panic("Vulkan function call failed: Device.GetSwapchainImagesKHR 2");

    // Image views
    var view_info: vk.ImageViewCreateInfo = .{
        .view_type = .@"2d",
        .format = swapchain_data.format.?,
        .components = .{
            .r = .r,
            .g = .g,
            .b = .b,
            .a = .a,
        },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true, },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        // zero init
        .image = .null_handle,
    };

    {
        var i: u32 = 0;
        while (i < swapchain_data.image_count.?) : (i += 1)
        {
            view_info.image = swapchain_data.images.get(i);
            swapchain_data.image_views.set
            (
                i,
                (
                    device_wrapper.createImageView(device, &view_info, null)
                        catch @panic("Vulkan function call failed: Device.CreateImageView")
                )
            );
        }
    }

    // Framebuffers
    var fb_info: vk.FramebufferCreateInfo = .{
        .render_pass = swapchain_data.render_pass.?,
        .attachment_count = 1,
        .width = swapchain_data.width.?,
        .height = swapchain_data.height.?,
        .layers = 1,
    };

    {
        var i: u32 = 0;
        while (i < swapchain_data.image_count.?) : (i += 1)
        {
            fb_info.p_attachments = &@as([1]vk.ImageView, .{ swapchain_data.image_views.get(i), });
            swapchain_data.framebuffers.set
            (
                i,
                (
                    device_wrapper.createFramebuffer(device, &fb_info, null)
                        catch @panic("Vulkan function call failed: Device.CreateFramebuffer")
                )
            );
        }
    }

    // Command buffer pool
    const cmd_buffer_pool_info: vk.CommandPoolCreateInfo = .{
        .flags = .{ .reset_command_buffer_bit = true, },
        .queue_family_index = g_graphic_queue.queue_family_index,
    };
    swapchain_data.command_pool = device_wrapper.createCommandPool(device, &cmd_buffer_pool_info, null)
        catch @panic("Vulkan function call failed: Device.CreateCommandPool");
}

pub fn destroy_swapchain
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    swapchain_data: *vkt.SwapchainData,
    g_previous_draw_data: *?vkt.DrawData,
)
void
{
    if (g_previous_draw_data.* != null)
    {
        device_wrapper.destroySemaphore(device, g_previous_draw_data.*.?.cross_engine_semaphore, null);
        device_wrapper.destroySemaphore(device, g_previous_draw_data.*.?.semaphore, null);
        device_wrapper.destroyFence(device, g_previous_draw_data.*.?.fence, null);
        device_wrapper.destroyBuffer(device, g_previous_draw_data.*.?.vertex_buffer, null);
        device_wrapper.destroyBuffer(device, g_previous_draw_data.*.?.index_buffer, null);
        device_wrapper.freeMemory(device, g_previous_draw_data.*.?.vertex_buffer_mem, null);
        device_wrapper.freeMemory(device, g_previous_draw_data.*.?.index_buffer_mem, null);
        g_previous_draw_data.* = null;
    }

    for (swapchain_data.image_views.slice()) |iv|
    {
        device_wrapper.destroyImageView(device, iv, null);
    }
    swapchain_data.image_views.len = 0;

    for (swapchain_data.framebuffers.slice()) |fb|
    {
        device_wrapper.destroyFramebuffer(device, fb, null);
    }
    swapchain_data.framebuffers.len = 0;

    if (swapchain_data.render_pass != null)
    {
        device_wrapper.destroyRenderPass(device, swapchain_data.render_pass.?, null);
        swapchain_data.render_pass = null;
    }

    if (swapchain_data.command_pool != null)
    {
        device_wrapper.destroyCommandPool(device, swapchain_data.command_pool.?, null);
        swapchain_data.command_pool = null;
    }

    if (swapchain_data.pipeline != null)
    {
        device_wrapper.destroyPipeline(device, swapchain_data.pipeline.?, null);
        swapchain_data.pipeline = null;
    }

    if (swapchain_data.pipeline_layout != null)
    {
        device_wrapper.destroyPipelineLayout(device, swapchain_data.pipeline_layout.?, null);
        swapchain_data.pipeline_layout = null;
    }

    if (swapchain_data.descriptor_pool != null)
    {
        device_wrapper.destroyDescriptorPool(device, swapchain_data.descriptor_pool.?, null);
        swapchain_data.descriptor_pool = null;
    }

    if (swapchain_data.descriptor_layout != null)
    {
        device_wrapper.destroyDescriptorSetLayout(device, swapchain_data.descriptor_layout.?, null);
        swapchain_data.descriptor_layout = null;
    }

    if (swapchain_data.font_sampler != null)
    {
        device_wrapper.destroySampler(device, swapchain_data.font_sampler.?, null);
        swapchain_data.font_sampler = null;
    }

    if (swapchain_data.font_image_view != null)
    {
        device_wrapper.destroyImageView(device, swapchain_data.font_image_view.?, null);
        swapchain_data.font_image_view = null;
    }

    if (swapchain_data.font_image != null)
    {
        device_wrapper.destroyImage(device, swapchain_data.font_image.?, null);
        swapchain_data.font_image = null;
    }

    if (swapchain_data.font_mem != null)
    {
        device_wrapper.freeMemory(device, swapchain_data.font_mem.?, null);
        swapchain_data.font_mem = null;
    }

    if (swapchain_data.upload_font_buffer != null)
    {
        device_wrapper.destroyBuffer(device, swapchain_data.upload_font_buffer.?, null);
        swapchain_data.upload_font_buffer = null;
    }

    if (swapchain_data.upload_font_buffer_mem != null)
    {
        device_wrapper.freeMemory(device, swapchain_data.upload_font_buffer_mem.?, null);
        swapchain_data.upload_font_buffer_mem = null;
    }
}

pub fn destroy_instance
(
    instance: vk.Instance,
    instance_wrapper: vkt.LayerInstanceWrapper,
)
void
{
    _ = instance;
    _ = instance_wrapper;
}

pub fn device_map_queues
(
    p_create_info: *const vk.DeviceCreateInfo,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    set_device_loader_data_func: vkl.PfnSetDeviceLoaderData,
    instance_wrapper: vkt.LayerInstanceWrapper,
    device_wrapper: vkt.LayerDeviceWrapper,
    g_queues: *vkt.VkQueueDataBacking,
    g_graphic_queue: *?*vkt.VkQueueData,
)
void
{
    var queue_family_props_count: u32 = 0;
    instance_wrapper.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_props_count, null);

    var family_props = vkt.VkQueueFamilyPropsBacking.init(0)
        catch @panic("Failed to get backing buffer for QueueFamilyProperties");
    family_props.resize(queue_family_props_count)
        catch @panic("QueueFamilyProperties buffer overflow");

    instance_wrapper.getPhysicalDeviceQueueFamilyProperties
    (
        physical_device,
        &queue_family_props_count,
        family_props.slice().ptr,
    );

    var i: u32 = 0;
    while (i < p_create_info.queue_create_info_count) : (i += 1)
    {
        const queue_family_index = p_create_info.p_queue_create_infos[i].queue_family_index;
        var j: u32 = 0;
        while (j < p_create_info.p_queue_create_infos[i].queue_count) : (j += 1)
        {
            g_queues.resize(g_queues.len + 1)
                catch @panic("Failed to get backing buffer for device queues");
            var data = &g_queues.buffer[g_queues.len - 1];

            const queue = device_wrapper.getDeviceQueue(device, queue_family_index, j);
            const set_dvc_loader_result = set_device_loader_data_func(device, @intFromEnum(queue));
            if (set_dvc_loader_result != vk.Result.success)
            {
                @panic("Vulkan function call failed: Stubs.PfnSetDeviceLoaderData");
            }

            // Fence synchronizing access to queries on that queue.
            const fence_info: vk.FenceCreateInfo = .{ .flags = .{ .signaled_bit = true, }, };
            const fence = device_wrapper.createFence(device, &fence_info, null)
                catch @panic("Vulkan function call failed: Device.CreateFence");

            data.* = .{
                .device = device,
                .queue_family_index = queue_family_index,
                .queue_flags = family_props.buffer[queue_family_index].queue_flags,
                .queue = queue,
                .fence = fence,
            };

            if (data.queue_flags.contains(.{ .graphics_bit = true, }))
            {
                g_graphic_queue.* = data;
            }
        }
    }
}

pub fn map_physical_devices_to_instance(instance_data: *vkt.InstanceData) void
{
    var phy_device_count: u32 = 0;
    _ = instance_data.instance_wrapper.enumeratePhysicalDevices(instance_data.instance, &phy_device_count, null)
        catch @panic("Vulkan function call failed: Instance.PfnEnumeratePhysicalDevices 1");

    instance_data.physical_devices.resize(phy_device_count)
        catch @panic("PhysicalDevices buffer overflow");

    _ = instance_data.instance_wrapper.enumeratePhysicalDevices
    (
        instance_data.instance,
        &phy_device_count,
        instance_data.physical_devices.slice().ptr,
    )
        catch @panic("Vulkan function call failed: Instance.PfnEnumeratePhysicalDevices 2");
}

pub fn wait_before_queue_present
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    queue: vk.Queue,
    queue_data: *const vkt.VkQueueData,
)
void
{
    const fence_container: [1]vk.Fence = .{ queue_data.fence, };

    _ = device_wrapper.resetFences(device, 1, &fence_container)
        catch @panic("Vulkan function call failed: Device.ResetFences");

    device_wrapper.queueSubmit(queue, 0, null, queue_data.fence)
        catch @panic("Vulkan function call failed: Device.QueueSubmit");

    _ = device_wrapper.waitForFences(device, 1, &fence_container, 0, std.math.maxInt(u64))
        catch @panic("Vulkan function call failed: Device.WaitForFences");
}

fn get_overlay_draw
(
    device: vk.Device,
    set_device_loader_data_func: vkl.PfnSetDeviceLoaderData,
    device_wrapper: vkt.LayerDeviceWrapper,
    swapchain_data: *const vkt.SwapchainData,
    g_previous_draw_data: *?vkt.DrawData,
)
vkt.DrawData
{
    if (g_previous_draw_data.*) |draw_data|
    {
        const get_fence_result = device_wrapper.getFenceStatus(device, draw_data.fence)
            catch @panic("Vulkan function call failed: Device.GetFenceStatus");

        if (get_fence_result == vk.Result.success)
        {
            const fence_container = [1]vk.Fence
            {
                draw_data.fence,
            };
            device_wrapper.resetFences(device, 1, &fence_container)
                catch @panic("Vulkan function call failed: Device.ResetFences");

            return draw_data;
        }
    }

    var draw_data: vkt.DrawData = .{};

    const cmd_buffer_info: vk.CommandBufferAllocateInfo = .{
        .command_pool = swapchain_data.command_pool.?,
        .level = .primary,
        .command_buffer_count = 1,
    };
    var command_buf_container: [1]vk.CommandBuffer = .{ .null_handle, };
    device_wrapper.allocateCommandBuffers
    (
        device,
        &cmd_buffer_info,
        &command_buf_container,
    )
        catch @panic("Vulkan function call failed: Device.AllocateCommandBuffers");
    draw_data.command_buffer = command_buf_container[0];

    const set_dvc_loader_result = set_device_loader_data_func
    (
        device,
        @intFromEnum(draw_data.command_buffer),
    );
    if (set_dvc_loader_result != vk.Result.success)
    {
        @panic("Vulkan function call failed: Stubs.PfnSetDeviceLoaderData");
    }

    const fence_info: vk.FenceCreateInfo = .{};
    draw_data.fence = device_wrapper.createFence
    (
        device,
        &fence_info,
        null,
    )
        catch @panic("Vulkan function call failed: Device.CreateFence");

    const sem_info: vk.SemaphoreCreateInfo = .{};
    draw_data.semaphore = device_wrapper.createSemaphore(device, &sem_info, null)
        catch @panic("Vulkan function call failed: Device.CreateSemaphore 1");
    draw_data.cross_engine_semaphore = device_wrapper.createSemaphore
    (
        device,
        &sem_info,
        null,
    )
        catch @panic("Vulkan function call failed: Device.CreateSemaphore 2");

    g_previous_draw_data.* = draw_data;
    return g_previous_draw_data.*.?;
}

fn ensure_swapchain_fonts
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    command_buffer: vk.CommandBuffer,
    swapchain_data: *vkt.SwapchainData,
)
void
{
    if (swapchain_data.font_uploaded) return;

    var w: i32 = 0;
    var h: i32 = 0;
    const pixels = overlay_gui.setup_font_text_data(&w, &h)
        catch @panic("ImGui provided an invalid font size.");

    const upload_size: usize = @intCast(w * h * 4);

    const buffer_info: vk.BufferCreateInfo = .{
        .size = upload_size,
        .usage = .{ .transfer_src_bit = true, },
        .sharing_mode = .exclusive,
    };
    swapchain_data.upload_font_buffer = device_wrapper.createBuffer
    (
        device,
        &buffer_info,
        null,
    )
        catch @panic("Vulkan function call failed: Device.CreateBuffer");

    const upload_buffer_req = device_wrapper.getBufferMemoryRequirements
    (
        device,
        swapchain_data.upload_font_buffer.?,
    );

    const upload_alloc_info: vk.MemoryAllocateInfo = .{
        .allocation_size = upload_buffer_req.size,
        .memory_type_index = vkh.vk_memory_type
        (
            device,
            .{ .host_visible_bit = true, },
            upload_buffer_req.memory_type_bits
        ),
    };
    swapchain_data.upload_font_buffer_mem = device_wrapper.allocateMemory
    (
        device,
        &upload_alloc_info,
        null,
    )
        catch @panic("Vulkan function call failed: Device.AllocateMemory");

    device_wrapper.bindBufferMemory
    (
        device,
        swapchain_data.upload_font_buffer.?,
        swapchain_data.upload_font_buffer_mem.?,
        0,
    )
        catch @panic("Vulkan function call failed: Device.BindBufferMemory");

    var map: [*]u8 = @ptrCast
    (
        device_wrapper.mapMemory
        (
            device,
            swapchain_data.upload_font_buffer_mem.?,
            0,
            upload_size,
            .{},
        )
            catch @panic("Vulkan function call failed: Device.MapMemory")
    );

    @memcpy(map[0..upload_size], pixels[0..upload_size]);
    const range: [1]vk.MappedMemoryRange = .{
        .{
            .memory = swapchain_data.upload_font_buffer_mem.?,
            .size = upload_size,
            // zero init
            .offset = 0,
        },
    };
    device_wrapper.flushMappedMemoryRanges(device, 1, &range)
        catch @panic("Vulkan function call failed: Device.FlushMappedMemoryRanges");
    device_wrapper.unmapMemory(device, swapchain_data.upload_font_buffer_mem.?);

    const copy_barrier: [1]vk.ImageMemoryBarrier = .{
        .{
            .dst_access_mask = .{ .transfer_write_bit = true, },
            .old_layout = .undefined,
            .new_layout = .transfer_dst_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = swapchain_data.font_image.?,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true, },
                .level_count = 1,
                .layer_count = 1,
                // zero init
                .base_array_layer = 0,
                .base_mip_level = 0,
            },
            // zero init
            .src_access_mask = .{},
        },
    };
    device_wrapper.cmdPipelineBarrier
    (
        command_buffer,
        .{ .host_bit = true, },
        .{ .transfer_bit = true, },
        .{},
        0,
        null,
        0,
        null,
        1,
        &copy_barrier,
    );

    const region: [1]vk.BufferImageCopy = .{
        .{
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true, },
                .layer_count = 1,
                // zero init
                .mip_level = 0,
                .base_array_layer = 0,
            },
            .image_extent = .{
                .width = @as(u32, @intCast(w)),
                .height = @as(u32, @intCast(h)),
                .depth = @as(u32, 1),
            },
            // zero init
            .buffer_image_height = 0,
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .image_offset = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
        },
    };

    device_wrapper.cmdCopyBufferToImage
    (
        command_buffer,
        swapchain_data.upload_font_buffer.?,
        swapchain_data.font_image.?,
        .transfer_dst_optimal,
        1,
        &region,
    );

    const use_barrier: [1]vk.ImageMemoryBarrier = .{
        .{
            .src_access_mask = .{ .transfer_write_bit = true, },
            .dst_access_mask = .{ .shader_read_bit = true, },
            .old_layout = .transfer_dst_optimal,
            .new_layout = .shader_read_only_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = swapchain_data.font_image.?,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true, },
                .level_count = 1,
                .layer_count = 1,
                // zero init
                .base_array_layer = 0,
                .base_mip_level = 0,
            },
        },
    };
    device_wrapper.cmdPipelineBarrier
    (
        command_buffer,
        .{ .transfer_bit = true, },
        .{ .fragment_shader_bit = true, },
        .{},
        0,
        null,
        0,
        null,
        1,
        &use_barrier,
    );

    overlay_gui.set_fonts_tex_ident(@ptrCast(&swapchain_data.font_image.?));
    swapchain_data.font_uploaded = true;
}

fn create_or_resize_buffer
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    buffer: *vk.Buffer,
    buffer_mem: *vk.DeviceMemory,
    buffer_size: *vk.DeviceSize,
    new_size: u64,
    usage: vk.BufferUsageFlags,
)
void
{

    if (buffer.* != .null_handle)
    {
        device_wrapper.destroyBuffer(device, buffer.*, null);
    }

    if (@intFromEnum(buffer_mem.*) > 0)
    {
        device_wrapper.freeMemory(device, buffer_mem.*, null);
    }

    const buffer_info: vk.BufferCreateInfo = .{
        .size = new_size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };
    const create_buffer_result = device_wrapper.dispatch.vkCreateBuffer
    (
        device,
        &buffer_info,
        null,
        buffer,
    );
    if (create_buffer_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateBuffer");

    const req = device_wrapper.getBufferMemoryRequirements(device, buffer.*);
    const alloc_info: vk.MemoryAllocateInfo = .{
        .allocation_size = req.size,
        .memory_type_index = vkh.vk_memory_type
        (
            device,
            .{ .host_visible_bit = true, },
            req.memory_type_bits,
        ),
    };
    const alloc_mem_result = device_wrapper.dispatch.vkAllocateMemory(
        device,
        &alloc_info,
        null,
        buffer_mem,
    );
    if (alloc_mem_result != vk.Result.success) @panic("Vulkan function call failed: Device.AllocateMemory");

    device_wrapper.bindBufferMemory(device, buffer.*, buffer_mem.*, 0)
        catch @panic("Vulkan function call failed: Device.BindBufferMemory");

    buffer_size.* = new_size;
}

fn render_swapchain_display
(
    device: vk.Device,
    set_device_loader_data_func: vkl.PfnSetDeviceLoaderData,
    device_wrapper: vkt.LayerDeviceWrapper,
    queue_data: *const vkt.VkQueueData,
    p_wait_semaphores: ?[*]const vk.Semaphore,
    wait_semaphore_count: u32,
    image_index: u32,
    g_graphic_queue: *const vkt.VkQueueData,
    g_previous_draw_data: *?vkt.DrawData,
    swapchain_data: *vkt.SwapchainData,
)
?vkt.DrawData
{
    const imgui_draw_data = overlay_gui.get_draw_data();
    if (imgui_draw_data == null or imgui_draw_data.?.TotalVtxCount < 1) return null;

    var draw_data = get_overlay_draw
    (
        device,
        set_device_loader_data_func,
        device_wrapper,
        swapchain_data,
        g_previous_draw_data,
    );

    device_wrapper.resetCommandBuffer(draw_data.command_buffer, .{})
        catch @panic("Vulkan function call failed: Device.ResetCommandBuffer");

    const render_pass_info: vk.RenderPassBeginInfo = .{
        .render_pass = swapchain_data.render_pass.?,
        .framebuffer = swapchain_data.framebuffers.get(image_index),
        .render_area = .{
            .extent = .{
                .width = swapchain_data.width.?,
                .height = swapchain_data.height.?,
            },
            // zero init
            .offset = .{
                .x = 0,
                .y = 0,
            },
        },
    };

    const buffer_begin_info: vk.CommandBufferBeginInfo = .{};
    device_wrapper.beginCommandBuffer(draw_data.command_buffer, &buffer_begin_info)
        catch @panic("Vulkan function call failed: Device.BeginCommandBuffer");

    ensure_swapchain_fonts
    (
        device,
        device_wrapper,
        draw_data.command_buffer,
        swapchain_data,
    );

    {
        const imb_container: [1]vk.ImageMemoryBarrier = .{
            .{
                .src_access_mask = .{ .color_attachment_write_bit = true, },
                .dst_access_mask = .{ .color_attachment_write_bit = true, },
                .old_layout = .present_src_khr,
                .new_layout = .color_attachment_optimal,
                .src_queue_family_index = queue_data.queue_family_index,
                .dst_queue_family_index = g_graphic_queue.queue_family_index,
                .image = swapchain_data.images.get(image_index),
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true, },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            },
        };
        device_wrapper.cmdPipelineBarrier
        (
            draw_data.command_buffer,
            .{ .all_graphics_bit = true, },
            .{ .all_graphics_bit = true, },
            .{},
            0,
            null,
            0,
            null,
            1,
            &imb_container,
        );
    }

    device_wrapper.cmdBeginRenderPass(draw_data.command_buffer, &render_pass_info, .@"inline");

    const vertex_size: u64 = @as(u64, @intCast(imgui_draw_data.?.TotalVtxCount)) * @sizeOf(overlay_gui.DrawVert);
    const index_size: u64 = @as(u64, @intCast(imgui_draw_data.?.TotalIdxCount)) * @sizeOf(overlay_gui.DrawIdx);

    if (draw_data.vertex_buffer_size < vertex_size)
    {
        create_or_resize_buffer
        (
            device,
            device_wrapper,
            &draw_data.vertex_buffer,
            &draw_data.vertex_buffer_mem,
            &draw_data.vertex_buffer_size,
            vertex_size,
            .{ .vertex_buffer_bit = true, },
        );
    }

    if (draw_data.index_buffer_size < index_size)
    {
        create_or_resize_buffer
        (
            device,
            device_wrapper,
            &draw_data.index_buffer,
            &draw_data.index_buffer_mem,
            &draw_data.index_buffer_size,
            index_size,
            .{ .index_buffer_bit = true, },
        );
    }

    var vertex_dst: [*]overlay_gui.DrawVert = @ptrCast
    (
        @alignCast
        (
            device_wrapper.mapMemory
            (
                device,
                draw_data.vertex_buffer_mem,
                0,
                vertex_size,
                .{},
            )
                catch @panic("Vulkan function call failed: Device.MapMemory 1")
        ),
    );

    var index_dst: [*]overlay_gui.DrawIdx = @ptrCast
    (
        @alignCast
        (
            device_wrapper.mapMemory
            (
                device,
                draw_data.index_buffer_mem,
                0,
                index_size,
                .{},
            )
                catch @panic("Vulkan function call failed: Device.MapMemory 2")
        ),
    );

    for (overlay_gui.get_draw_data_draw_list(imgui_draw_data.?)) |cmd_list|
    {
        const vertex_buf = overlay_gui.get_draw_list_vertex_buffer(cmd_list.?);
        const index_buf = overlay_gui.get_draw_list_index_buffer(cmd_list.?);
        @memcpy(vertex_dst[0..vertex_buf.len], vertex_buf);
        @memcpy(index_dst[0..index_buf.len], index_buf);
        vertex_dst += vertex_buf.len;
        index_dst += index_buf.len;
    }

    const range: [2]vk.MappedMemoryRange = .{
        .{
            .memory = draw_data.vertex_buffer_mem,
            .size = vk.WHOLE_SIZE,
            // zero init
            .offset = 0,
        },
        .{
            .memory = draw_data.index_buffer_mem,
            .size = vk.WHOLE_SIZE,
            // zero init
            .offset = 0,
        },
    };

    device_wrapper.flushMappedMemoryRanges(device, 2, &range)
        catch @panic("Vulkan function call failed: Device.FlushMappedMemoryRanges");
    device_wrapper.unmapMemory(device, draw_data.vertex_buffer_mem);
    device_wrapper.unmapMemory(device, draw_data.index_buffer_mem);

    device_wrapper.cmdBindPipeline(draw_data.command_buffer, .graphics, swapchain_data.pipeline.?);
    const desc_set_container: [1]vk.DescriptorSet = .{ swapchain_data.descriptor_set.?, };
    device_wrapper.cmdBindDescriptorSets
    (
        draw_data.command_buffer,
        .graphics,
        swapchain_data.pipeline_layout.?,
        0,
        1,
        &desc_set_container,
        0,
        null,
    );

    const vertex_buffers_container: [1]vk.Buffer = .{ draw_data.vertex_buffer, };
    const vertex_offset_container: [1]vk.DeviceSize = .{ 0, };
    device_wrapper.cmdBindVertexBuffers
    (
        draw_data.command_buffer,
        0,
        1,
        &vertex_buffers_container,
        &vertex_offset_container,
    );
    device_wrapper.cmdBindIndexBuffer(draw_data.command_buffer, draw_data.index_buffer, 0, .uint16);

    const viewport_container: [1]vk.Viewport = .{
        .{
            .x = 0,
            .y = 0,
            .width = imgui_draw_data.?.DisplaySize.x,
            .height = imgui_draw_data.?.DisplaySize.y,
            .min_depth = 0.0,
            .max_depth = 1.0,
        },
    };
    device_wrapper.cmdSetViewport(draw_data.command_buffer, 0, 1, &viewport_container);

    const scale: [2]f32 = .{
        2.0 / imgui_draw_data.?.DisplaySize.x,
        2.0 / imgui_draw_data.?.DisplaySize.y,
    };
    device_wrapper.cmdPushConstants
    (
        draw_data.command_buffer,
        swapchain_data.pipeline_layout.?,
        .{ .vertex_bit = true, },
        @sizeOf(f32) * 0, // can't this just be 0?
        @sizeOf(f32) * 2,
        std.mem.asBytes(&scale),
    );

    const translate: [2]f32 = .{ -1.0, -1.0 };
    device_wrapper.cmdPushConstants
    (
        draw_data.command_buffer,
        swapchain_data.pipeline_layout.?,
        .{ .vertex_bit = true, },
        @sizeOf(f32) * 2,
        @sizeOf(f32) * 2,
        std.mem.asBytes(&translate),
    );

    {
        var vertex_offset: u32 = 0;
        var index_offset: u32 = 0;
        for (overlay_gui.get_draw_data_draw_list(imgui_draw_data.?)) |cmd_list|
        {
            for (overlay_gui.get_draw_list_command_buffer(cmd_list.?)) |cmd|
            {
                const x_pos: i32 = @intFromFloat(cmd.ClipRect.x - imgui_draw_data.?.DisplayPos.x);
                const y_pos: i32 = @intFromFloat(cmd.ClipRect.y - imgui_draw_data.?.DisplayPos.y);
                const scissor: [1]vk.Rect2D = .{
                    .{
                        .offset = .{
                            .x = if (x_pos > 0) x_pos else 0,
                            .y = if (y_pos > 0) y_pos else 0,
                        },
                        .extent = .{
                            .width = @intFromFloat(cmd.ClipRect.z - cmd.ClipRect.x),
                            .height = @intFromFloat(cmd.ClipRect.w - cmd.ClipRect.y + 1.0),
                        },
                    },
                };
                device_wrapper.cmdSetScissor(draw_data.command_buffer, 0, 1, &scissor);

                device_wrapper.cmdDrawIndexed
                (
                    draw_data.command_buffer,
                    cmd.ElemCount,
                    1,
                    index_offset,
                    @intCast(vertex_offset),
                    0,
                );

                index_offset += cmd.ElemCount;
            }

            vertex_offset += @intCast(overlay_gui.get_draw_list_vertex_buffer(cmd_list.?).len);
        }
    }

    device_wrapper.cmdEndRenderPass(draw_data.command_buffer);

    if (g_graphic_queue.queue_family_index != queue_data.queue_family_index)
    {
        const imb_container: [1]vk.ImageMemoryBarrier = .{
            .{
                .src_access_mask = .{ .color_attachment_write_bit = true, },
                .dst_access_mask = .{ .color_attachment_write_bit = true, },
                .old_layout = .present_src_khr,
                .new_layout = .present_src_khr,
                .src_queue_family_index = g_graphic_queue.queue_family_index,
                .dst_queue_family_index = queue_data.queue_family_index,
                .image = swapchain_data.images.get(image_index),
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true, },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            },
        };
        device_wrapper.cmdPipelineBarrier
        (
            draw_data.command_buffer,
            .{ .all_graphics_bit = true, },
            .{ .all_graphics_bit = true, },
            .{},
            0,
            null,
            0,
            null,
            1,
            &imb_container,
        );
    }

    device_wrapper.endCommandBuffer(draw_data.command_buffer)
        catch @panic("Vulkan function call failed: Device.EndCommandBuffer");

    if (wait_semaphore_count == 0 and g_graphic_queue.queue != queue_data.queue)
    {
        const stages_wait_container: [1]vk.PipelineStageFlags = .{ .{ .all_commands_bit = true, }, };
        const ce_semaphore_container: [1]vk.Semaphore = .{ draw_data.cross_engine_semaphore, };
        const submit_info_container1: [1]vk.SubmitInfo = .{
            .{
                .wait_semaphore_count = 0,
                .p_wait_dst_stage_mask = &stages_wait_container,
                .command_buffer_count = 0,
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &ce_semaphore_container,
            },
        };

        device_wrapper.queueSubmit(queue_data.queue, 1, &submit_info_container1, .null_handle)
            catch @panic("Vulkan function call failed: Device.QueueSubmit 1");

        const command_buf_container: [1]vk.CommandBuffer = .{ draw_data.command_buffer, };
        const semaphore_container: [1]vk.Semaphore = .{ draw_data.semaphore, };
        const submit_info_container2: [1]vk.SubmitInfo = .{
            .{
                .wait_semaphore_count = 1,
                .p_wait_semaphores = &ce_semaphore_container,
                .p_wait_dst_stage_mask = &stages_wait_container,
                .command_buffer_count = 1,
                .p_command_buffers = &command_buf_container,
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &semaphore_container,
            },
        };

        device_wrapper.queueSubmit(g_graphic_queue.queue, 1, &submit_info_container2, draw_data.fence)
            catch @panic("Vulkan function call failed: Device.QueueSubmit 2");
    }
    else
    {
        var stages_wait_backing = vkt.PipelineStageFlagsBacking.init(0)
            catch @panic("Failed to get backing buffer for PipelineStageFlags");
        stages_wait_backing.resize(wait_semaphore_count)
            catch @panic("PipelineStageFlags buffer overflow");

        {
            var i: u32 = 0;
            while (i < wait_semaphore_count) : (i += 1)
            {
                stages_wait_backing.buffer[i] = .{ .fragment_shader_bit = true, };
            }
        }

        const command_buf_container: [1]vk.CommandBuffer = .{ draw_data.command_buffer, };
        const semaphore_container: [1]vk.Semaphore = .{ draw_data.semaphore, };
        const submit_info_container: [1]vk.SubmitInfo = .{
            .{
                .wait_semaphore_count = wait_semaphore_count,
                .p_wait_semaphores = p_wait_semaphores,
                .p_wait_dst_stage_mask = stages_wait_backing.constSlice().ptr,
                .command_buffer_count = 1,
                .p_command_buffers = &command_buf_container,
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &semaphore_container,
            },
        };

        device_wrapper.queueSubmit(g_graphic_queue.queue, 1, &submit_info_container, draw_data.fence)
            catch @panic("Vulkan function call failed: Device.QueueSubmit");
    }

    return draw_data;
}

pub fn before_present
(
    device: vk.Device,
    set_device_loader_data_func: vkl.PfnSetDeviceLoaderData,
    device_wrapper: vkt.LayerDeviceWrapper,
    queue_data: *vkt.VkQueueData,
    p_wait_semaphores: ?[*]const vk.Semaphore,
    wait_semaphore_count: u32,
    image_index: u32,
    g_graphic_queue: *const vkt.VkQueueData,
    g_previous_draw_data: *?vkt.DrawData,
    swapchain_data: *vkt.SwapchainData,
    free_font_allocator_fn: *const fn () void,
)
!?vkt.DrawData
{
    if (swapchain_data.image_count.? > 0)
    {
        // calling this should be idempotent
        overlay_gui.create_overlay_context
        (
            @floatFromInt(swapchain_data.width.?),
            @floatFromInt(swapchain_data.height.?),
        );
        const old_ctx = overlay_gui.use_overlay_context()
            catch unreachable;
        defer overlay_gui.restore_old_context(old_ctx);

        overlay_gui.is_draw_ready()
            catch |err| switch (err)
            {
                error.FontNotLoaded => return null,
                error.FontTextureRequiresReload =>
                {
                    free_font_allocator_fn();
                    setup_swapchain_data_pipeline(device, device_wrapper, swapchain_data);
                    swapchain_data.font_uploaded = false;
                },
            };

        try overlay_gui.draw_frame
        (
            swapchain_data.width.?,
            swapchain_data.height.?,
        );

        const draw_data = render_swapchain_display
        (
            device,
            set_device_loader_data_func,
            device_wrapper,
            queue_data,
            p_wait_semaphores,
            wait_semaphore_count,
            image_index,
            g_graphic_queue,
            g_previous_draw_data,
            swapchain_data,
        );
        return draw_data;
    }

    return null;
}
