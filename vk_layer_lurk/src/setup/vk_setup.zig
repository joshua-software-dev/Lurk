const std = @import("std");

const embedded_shaders = @import("vk_embedded_shaders.zig");
const imgui_holder = @import("../imgui_holder.zig");
const vkh = @import("vk_helpers.zig");
const vkl = @import("vk_layer_stubs.zig");
const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


fn setup_swapchain_data_pipeline
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    g_descriptor_layout: *?vk.DescriptorSetLayout,
    g_descriptor_pool: *?vk.DescriptorPool,
    g_descriptor_set: *?vk.DescriptorSet,
    g_font_image_view: *?vk.ImageView,
    g_font_image: *?vk.Image,
    g_font_mem: *?vk.DeviceMemory,
    g_font_sampler: *?vk.Sampler,
    g_pipeline_layout: *?vk.PipelineLayout,
    g_pipeline: *?vk.Pipeline,
    g_render_pass: *?vk.RenderPass,
)
void
{
    // Create shader modules
    const frag_info = vk.ShaderModuleCreateInfo
    {
        .code_size = embedded_shaders.overlay_frag_spv.len * @sizeOf(u32),
        .p_code = embedded_shaders.overlay_frag_spv.ptr,
    };
    const frag_module = device_wrapper.createShaderModule(device, &frag_info, null)
    catch @panic("Vulkan function call failed: Device.CreateShaderModule | frag shader");

    const vert_info = vk.ShaderModuleCreateInfo
    {
        .code_size = embedded_shaders.overlay_vert_spv.len * @sizeOf(u32),
        .p_code = embedded_shaders.overlay_vert_spv.ptr,
    };
    const vert_module = device_wrapper.createShaderModule(device, &vert_info, null)
    catch @panic("Vulkan function call failed: Device.CreateShaderModule | vert shader");

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

    g_font_sampler.* = device_wrapper.createSampler(device, &font_sampler_info, null)
    catch @panic("Vulkan function call failed: Device.CreateSampler");

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

    g_descriptor_pool.* = device_wrapper.createDescriptorPool(device, &desc_pool_info, null)
    catch @panic("Vulkan function call failed: Device.CreateDescriptorPool");

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
                .p_immutable_samplers = &[1]vk.Sampler{ g_font_sampler.*.?, },
            },
        ),
    };
    const set_layout_info = vk.DescriptorSetLayoutCreateInfo
    {
        .binding_count = 1,
        .p_bindings = &binding,
    };
    g_descriptor_layout.* = device_wrapper.createDescriptorSetLayout(device, &set_layout_info, null)
    catch @panic("Vulkan function call failed: Device.CreateDescriptorSetLayout");

    // Descriptor set
    const alloc_info = vk.DescriptorSetAllocateInfo
    {
        .descriptor_pool = g_descriptor_pool.*.?,
        .descriptor_set_count = 1,
        .p_set_layouts = &[1]vk.DescriptorSetLayout{ g_descriptor_layout.*.?, },
    };

    var descriptor_set_container = [1]vk.DescriptorSet
    {
        vk.DescriptorSet.null_handle,
    };
    device_wrapper.allocateDescriptorSets(device, &alloc_info, &descriptor_set_container)
    catch @panic("Vulkan function call failed: Device.AllocateDescriptorSets");
    g_descriptor_set.* = descriptor_set_container[0];

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
        .p_set_layouts = &[1]vk.DescriptorSetLayout{ g_descriptor_layout.*.?, },
        .push_constant_range_count = 1,
        .p_push_constant_ranges = &push_constants,
    };
    g_pipeline_layout.* = device_wrapper.createPipelineLayout(device, &layout_info, null)
    catch @panic("Vulkan function call failed: Device.CreatePipelineLayout");

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
                .stride = imgui_holder.DrawVertSize,
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
            .offset = imgui_holder.DrawVertOffsetOfPos,
        },
        vk.VertexInputAttributeDescription
        {
            .location = 1,
            .binding = binding_desc[0].binding,
            .format = .r32g32_sfloat,
            .offset = imgui_holder.DrawVertOffsetOfUv,
        },
        vk.VertexInputAttributeDescription
        {
            .location = 2,
            .binding = binding_desc[0].binding,
            .format = .r8g8b8a8_unorm,
            .offset = imgui_holder.DrawVertOffsetOfColor,
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
        },
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
        },
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
                .layout = g_pipeline_layout.*.?,
                .render_pass = g_render_pass.*.?,
            }
        ),
    };
    var pipeline_container = [1]vk.Pipeline
    {
        vk.Pipeline.null_handle,
    };
    _ = device_wrapper.createGraphicsPipelines(device, .null_handle, 1, &info_container, null, &pipeline_container)
    catch @panic("Vulkan function call failed: Device.CreateGraphicsPipelines");
    g_pipeline.* = pipeline_container[0];

    device_wrapper.destroyShaderModule(device, vert_module, null);
    device_wrapper.destroyShaderModule(device, frag_module, null);

    var h: i32 = 0;
    var w: i32 = 0;
    _ = imgui_holder.setup_font_text_data(&w, &h) catch @panic("ImGui provided an invalid font size.");

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
    g_font_image.* = device_wrapper.createImage(device, &image_info, null)
    catch @panic("Vulkan function call failed: Device.CreateImage");

    var font_image_req = device_wrapper.getImageMemoryRequirements(device, g_font_image.*.?);

    const image_alloc_info = vk.MemoryAllocateInfo
    {
        .allocation_size = font_image_req.size,
        .memory_type_index = vkh.vk_memory_type
        (
            vk.MemoryPropertyFlags{ .device_local_bit = true, },
            font_image_req.memory_type_bits
        ),
    };
    g_font_mem.* = device_wrapper.allocateMemory(device, &image_alloc_info, null)
    catch @panic("Vulkan function call failed: Device.AllocateMemory");

    device_wrapper.bindImageMemory(device, g_font_image.*.?, g_font_mem.*.?, 0)
    catch @panic("Vulkan function call failed: Device.BindImageMemory");

    // Font image view
    const view_info = std.mem.zeroInit
    (
        vk.ImageViewCreateInfo,
        .{
            .image = g_font_image.*.?,
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
    g_font_image_view.* = device_wrapper.createImageView(device, &view_info, null)
    catch @panic("Vulkan function call failed: Device.CreateImageView");

    // Descriptor set
    const desc_image = [1]vk.DescriptorImageInfo
    {
        vk.DescriptorImageInfo
        {
            .sampler = g_font_sampler.*.?,
            .image_view = g_font_image_view.*.?,
            .image_layout = .shader_read_only_optimal,
        },
    };
    const write_desc = [1]vk.WriteDescriptorSet
    {
        std.mem.zeroInit
        (
            vk.WriteDescriptorSet,
            .{
                .dst_set = g_descriptor_set.*.?,
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
    device_wrapper.updateDescriptorSets(device, 1, &write_desc, 0, null);
}

pub fn setup_swapchain
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    p_create_info: *const vk.SwapchainCreateInfoKHR,
    g_command_pool: *?vk.CommandPool,
    g_descriptor_layout: *?vk.DescriptorSetLayout,
    g_descriptor_pool: *?vk.DescriptorPool,
    g_descriptor_set: *?vk.DescriptorSet,
    g_font_image_view: *?vk.ImageView,
    g_font_image: *?vk.Image,
    g_font_mem: *?vk.DeviceMemory,
    g_font_sampler: *?vk.Sampler,
    g_format: *?vk.Format,
    g_framebuffers: *vkt.FramebufferBacking,
    g_graphic_queue: *?vkt.QueueData,
    g_height: *?u32,
    g_image_count: *?u32,
    g_image_views: *vkt.ImageViewBacking,
    g_images: *vkt.ImageBacking,
    g_pipeline_layout: *?vk.PipelineLayout,
    g_pipeline: *?vk.Pipeline,
    g_render_pass: *?vk.RenderPass,
    g_swapchain: *?vk.SwapchainKHR,
    g_width: *?u32,
)
void
{
    g_height.* = p_create_info.image_extent.height;
    g_width.* = p_create_info.image_extent.width;
    g_format.* = p_create_info.image_format;

    imgui_holder.setup_context(@floatFromInt(g_width.*.?), @floatFromInt(g_height.*.?));

    const attachment_desc = [1]vk.AttachmentDescription
    {
        vk.AttachmentDescription
        {
            .format = g_format.*.?,
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

    g_render_pass.* = device_wrapper.createRenderPass(device, &render_pass_info, null)
    catch @panic("Vulkan function call failed: Device.CreateRenderPass");

    setup_swapchain_data_pipeline
    (
        device,
        device_wrapper,
        g_descriptor_layout,
        g_descriptor_pool,
        g_descriptor_set,
        g_font_image_view,
        g_font_image,
        g_font_mem,
        g_font_sampler,
        g_pipeline_layout,
        g_pipeline,
        g_render_pass,
    );

    g_image_count.* = 0;
    _ = device_wrapper.getSwapchainImagesKHR
    (
        device,
        g_swapchain.*.?,
        &(g_image_count.*.?),
        null,
    )
    catch @panic("Vulkan function call failed: Device.GetSwapchainImagesKHR 1");

    g_framebuffers.resize(g_image_count.*.?)
    catch @panic("Framebuffer buffer overflow");
    g_image_views.resize(g_image_count.*.?)
    catch @panic("Image View buffer overflow");
    g_images.resize(g_image_count.*.?)
    catch @panic("Image buffer overflow");

    _ = device_wrapper.getSwapchainImagesKHR
    (
        device,
        g_swapchain.*.?,
        &(g_image_count.*.?),
        &g_images.buffer,
    )
    catch @panic("Vulkan function call failed: Device.GetSwapchainImagesKHR 2");

    // Image views
    var view_info = std.mem.zeroInit
    (
        vk.ImageViewCreateInfo,
        .{
            .view_type = .@"2d",
            .format = g_format.*.?,
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
        while (i < g_image_count.*.?) : (i += 1)
        {
            view_info.image = g_images.buffer[i];
            g_image_views.buffer[i] = device_wrapper.createImageView(device, &view_info, null)
            catch @panic("Vulkan function call failed: Device.CreateImageView");
        }
    }

    // Framebuffers
    var fb_info = vk.FramebufferCreateInfo
    {
        .render_pass = g_render_pass.*.?,
        .attachment_count = 1,
        .width = g_width.*.?,
        .height = g_height.*.?,
        .layers = 1,
    };

    {
        var i: u32 = 0;
        while (i < g_image_count.*.?) : (i += 1)
        {
            fb_info.p_attachments = g_image_views.buffer[i..i].ptr;
            g_framebuffers.buffer[i] = device_wrapper.createFramebuffer(device, &fb_info, null)
            catch @panic("Vulkan function call failed: Device.CreateFramebuffer");
        }
    }

    // Command buffer pool
    const cmd_buffer_pool_info = vk.CommandPoolCreateInfo
    {
        .flags = vk.CommandPoolCreateFlags{ .reset_command_buffer_bit = true, },
        .queue_family_index = g_graphic_queue.*.?.queue_family_index,
    };
    g_command_pool.* = device_wrapper.createCommandPool(device, &cmd_buffer_pool_info, null)
    catch @panic("Vulkan function call failed: Device.CreateCommandPool");
}

pub fn destroy_swapchain
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    g_render_pass: *?vk.RenderPass,
)
void
{
    std.log.scoped(.LAYER).debug("Destroying render pass...", .{});
    device_wrapper.destroyRenderPass(device, g_render_pass.*.?, null);
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
    _ = imgui_holder.destroy_context();
}

pub fn get_physical_mem_props
(
    physical_device: vk.PhysicalDevice,
    instance_wrapper: vkt.LayerInstanceWrapper,
)
void
{
    vkh.physical_mem_props = instance_wrapper.getPhysicalDeviceMemoryProperties(physical_device);
}

fn new_queue_data
(
    data: *vkt.QueueData,
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    g_graphic_queue: *?vkt.QueueData,
)
void
{
    // Fence synchronizing access to queries on that queue.
    const fence_info = vk.FenceCreateInfo
    {
        .flags = vk.FenceCreateFlags{ .signaled_bit = true, },
    };
    data.fence = device_wrapper.createFence(device, &fence_info, null)
    catch @panic("Vulkan function call failed: Device.CreateFence");

    if (data.queue_flags.contains(vk.QueueFlags{ .graphics_bit = true,}))
    {
        g_graphic_queue.* = data.*;
    }
}

pub fn device_map_queues
(
    p_create_info: *const vk.DeviceCreateInfo,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    init_wrapper: vkl.LayerInitWrapper,
    instance_wrapper: vkt.LayerInstanceWrapper,
    g_device_queues: *vkt.QueueDataBacking,
    g_graphic_queue: *?vkt.QueueData,
)
void
{
    var queue_family_props_count: u32 = 0;
    instance_wrapper.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_props_count, null);

    var family_props = vkt.QueueFamilyPropsBacking.init(0)
    catch @panic("Failed to get backing buffer for QueueFamilyProperties");
    family_props.resize(queue_family_props_count) catch @panic("QueueFamilyProperties buffer overflow");

    instance_wrapper.getPhysicalDeviceQueueFamilyProperties
    (
        physical_device,
        &queue_family_props_count,
        family_props.slice().ptr,
    );

    var device_queue_index: u32 = 0;
    var i: u32 = 0;
    while (i < p_create_info.queue_create_info_count) : (i += 1)
    {
        const queue_family_index = p_create_info.p_queue_create_infos[i].queue_family_index;
        var j: u32 = 0;
        while (j < p_create_info.p_queue_create_infos[i].queue_count) : ({j += 1; device_queue_index += 1;})
        {
            g_device_queues.resize(device_queue_index + 1)
            catch @panic("QueueDataBacking buffer overflow");

            var data = &g_device_queues.buffer[device_queue_index];
            data.* = std.mem.zeroInit
            (
                vkt.QueueData,
                .{
                    .queue_family_index = queue_family_index,
                    .queue_flags = family_props.buffer[queue_family_index].queue_flags,
                },
            );

            var original_queue: vk.Queue = device_wrapper.getDeviceQueue(device, queue_family_index, j);
            data.queue = original_queue;

            const set_dvc_loader_result = init_wrapper.pfn_set_device_loader_data(device, &original_queue);
            if (set_dvc_loader_result != vk.Result.success)
            {
                @panic("Vulkan function call failed: Stubs.PfnSetDeviceLoaderData");
            }

            new_queue_data(data, device, device_wrapper, g_graphic_queue);
        }
    }
}

/// The backing for this should likely be replaced with a hashmap, but the
/// common case is that there is only 1 item in the buffer, so its somewhat
/// moot at the moment.
fn get_queue_data
(
    queue: vk.Queue,
    g_device_queues: *vkt.QueueDataBacking,
)
vkt.QueueData
{
    for (g_device_queues.constSlice()) |it|
    {
        if(it.queue == queue) return it;
    }

    @panic("Lookup failed for VkQueue<->VkDevice mapping");
}

pub fn wait_before_queue_present
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    queue: vk.Queue,
    g_device_queues: *vkt.QueueDataBacking,
)
vkt.QueueData
{
    const queue_data = get_queue_data(queue, g_device_queues);
    const fence_container = [1]vk.Fence
    {
        queue_data.fence,
    };

    _ = device_wrapper.resetFences(device, 1, &fence_container)
    catch @panic("Vulkan function call failed: Device.ResetFences");

    device_wrapper.queueSubmit(queue, 0, null, queue_data.fence)
    catch @panic("Vulkan function call failed: Device.QueueSubmit");

    _ = device_wrapper.waitForFences(device, 1, &fence_container, 0, std.math.maxInt(u64))
    catch @panic("Vulkan function call failed: Device.WaitForFences");

    return queue_data;
}

fn get_overlay_draw
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    init_wrapper: vkl.LayerInitWrapper,
    g_command_pool: *?vk.CommandPool,
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

    var draw_data: vkt.DrawData = std.mem.zeroInit(vkt.DrawData, .{});

    const cmd_buffer_info = vk.CommandBufferAllocateInfo
    {
        .command_pool = g_command_pool.*.?,
        .level = .primary,
        .command_buffer_count = 1,
    };
    var command_buf_container = [1]vk.CommandBuffer
    {
        .null_handle,
    };
    device_wrapper.allocateCommandBuffers
    (
        device,
        &cmd_buffer_info,
        &command_buf_container,
    )
    catch @panic("Vulkan function call failed: Device.AllocateCommandBuffers");
    // its important to make sure to save the address of the buffer early
    draw_data.command_buffer = command_buf_container[0];

    // because for some reason this will mutate the address you give it...
    // but all subsequent calls need to be against the older address
    const set_dvc_loader_result = init_wrapper.pfn_set_device_loader_data
    (
        device,
        &command_buf_container[0],
    );
    if (set_dvc_loader_result != vk.Result.success)
    {
        @panic("Vulkan function call failed: Stubs.PfnSetDeviceLoaderData");
    }

    const fence_info = vk.FenceCreateInfo{};
    draw_data.fence = device_wrapper.createFence
    (
        device,
        &fence_info,
        null,
    )
    catch @panic("Vulkan function call failed: Device.CreateFence");

    const sem_info = vk.SemaphoreCreateInfo{};
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
    command_buffer: vk.CommandBuffer,
    device_wrapper: vkt.LayerDeviceWrapper,
    g_font_already_uploaded: *bool,
    g_font_image: *?vk.Image,
    g_upload_font_buffer_mem: *?vk.DeviceMemory,
    g_upload_font_buffer: *?vk.Buffer,
)
void
{
    if (g_font_already_uploaded.*) return;

    var w: i32 = 0;
    var h: i32 = 0;
    const pixels = imgui_holder.setup_font_text_data(&w, &h) catch @panic("ImGui provided an invalid font size.");
    const upload_size: u64 = @intCast(w * h * 4);

    const buffer_info = vk.BufferCreateInfo
    {
        .size = upload_size,
        .usage = vk.BufferUsageFlags{ .transfer_src_bit = true, },
        .sharing_mode = .exclusive,
    };
    g_upload_font_buffer.* = device_wrapper.createBuffer
    (
        device,
        &buffer_info,
        null,
    )
    catch @panic("Vulkan function call failed: Device.CreateBuffer");

    const upload_buffer_req = device_wrapper.getBufferMemoryRequirements
    (
        device,
        g_upload_font_buffer.*.?,
    );

    const upload_alloc_info = vk.MemoryAllocateInfo
    {
        .allocation_size = upload_buffer_req.size,
        .memory_type_index = vkh.vk_memory_type
        (
            vk.MemoryPropertyFlags{ .host_visible_bit = true, },
            upload_buffer_req.memory_type_bits
        ),
    };
    g_upload_font_buffer_mem.* = device_wrapper.allocateMemory
    (
        device,
        &upload_alloc_info,
        null,
    )
    catch @panic("Vulkan function call failed: Device.AllocateMemory");

    device_wrapper.bindBufferMemory
    (
        device,
        g_upload_font_buffer.*.?,
        g_upload_font_buffer_mem.*.?,
        0,
    )
    catch @panic("Vulkan function call failed: Device.BindBufferMemory");

    var map: [*]u8 = @ptrCast
    (
        device_wrapper.mapMemory
        (
            device,
            g_upload_font_buffer_mem.*.?,
            0,
            upload_size,
            .{},
        )
        catch @panic("Vulkan function call failed: Device.MapMemory")
    );

    @memcpy(map[0..upload_size], pixels[0..upload_size]);
    const range = [1]vk.MappedMemoryRange
    {
        std.mem.zeroInit
        (
            vk.MappedMemoryRange,
            .{
                .memory = g_upload_font_buffer_mem.*.?,
                .size = upload_size,
            },
        ),
    };
    device_wrapper.flushMappedMemoryRanges(device, 1, &range)
    catch @panic("Vulkan function call failed: Device.FlushMappedMemoryRanges");
    device_wrapper.unmapMemory(device, g_upload_font_buffer_mem.*.?);

    const copy_barrier = [1]vk.ImageMemoryBarrier
    {
        std.mem.zeroInit
        (
            vk.ImageMemoryBarrier,
            .{
                .dst_access_mask = vk.AccessFlags{ .transfer_write_bit = true, },
                .old_layout = .undefined,
                .new_layout = .transfer_dst_optimal,
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .image = g_font_image.*.?,
                .subresource_range = std.mem.zeroInit
                (
                    vk.ImageSubresourceRange,
                    .{
                        .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
                        .level_count = 1,
                        .layer_count = 1,
                    }
                ),
            },
        ),
    };
    device_wrapper.cmdPipelineBarrier
    (
        command_buffer,
        vk.PipelineStageFlags{ .host_bit = true, },
        vk.PipelineStageFlags{ .transfer_bit = true, },
        .{},
        0,
        null,
        0,
        null,
        1,
        &copy_barrier,
    );

    const region = [1]vk.BufferImageCopy
    {
        std.mem.zeroInit
        (
            vk.BufferImageCopy,
            .{
                .image_subresource = std.mem.zeroInit
                (
                    vk.ImageSubresourceLayers,
                    .{
                        .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
                        .layer_count = 1,
                    },
                ),
                .image_extent = vk.Extent3D
                {
                    .width = @intCast(w),
                    .height = @intCast(h),
                    .depth = 1,
                },
            },
        ),
    };

    device_wrapper.cmdCopyBufferToImage
    (
        command_buffer,
        g_upload_font_buffer.*.?,
        g_font_image.*.?,
        .transfer_dst_optimal,
        1,
        &region,
    );

    const use_barrier = [1]vk.ImageMemoryBarrier
    {
        std.mem.zeroInit
        (
            vk.ImageMemoryBarrier,
            .{
                .src_access_mask = vk.AccessFlags{ .transfer_write_bit = true, },
                .dst_access_mask = vk.AccessFlags{ .shader_read_bit = true, },
                .old_layout = .transfer_dst_optimal,
                .new_layout = .shader_read_only_optimal,
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .image = g_font_image.*.?,
                .subresource_range = std.mem.zeroInit
                (
                    vk.ImageSubresourceRange,
                    .{
                        .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
                        .level_count = 1,
                        .layer_count = 1,
                    }
                ),
            },
        ),
    };
    device_wrapper.cmdPipelineBarrier
    (
        command_buffer,
        vk.PipelineStageFlags{ .transfer_bit = true, },
        vk.PipelineStageFlags{ .fragment_shader_bit = true, },
        .{},
        0,
        null,
        0,
        null,
        1,
        &use_barrier,
    );

    imgui_holder.set_fonts_tex_ident(@ptrCast(&(g_font_image.*.?)));
    g_font_already_uploaded.* = true;
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

    if (buffer_mem.* != .null_handle)
    {
        device_wrapper.freeMemory(device, buffer_mem.*, null);
    }

    const buffer_info = vk.BufferCreateInfo
    {
        .size = new_size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };
    buffer.* = device_wrapper.createBuffer(device, &buffer_info, null)
    catch @panic("Vulkan function call failed: Device.CreateBuffer");

    const req = device_wrapper.getBufferMemoryRequirements(device, buffer.*);
    const alloc_info = vk.MemoryAllocateInfo
    {
        .allocation_size = req.size,
        .memory_type_index = vkh.vk_memory_type(vk.MemoryPropertyFlags{ .host_visible_bit = true, }, req.memory_type_bits),
    };
    buffer_mem.* = device_wrapper.allocateMemory(device, &alloc_info, null)
    catch @panic("Vulkan function call failed: Device.AllocateMemory");

    device_wrapper.bindBufferMemory(device, buffer.*, buffer_mem.*, 0)
    catch @panic("Vulkan function call failed: Device.BindBufferMemory");

    buffer_size.* = new_size;
}

fn render_swapchain_display
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    init_wrapper: vkl.LayerInitWrapper,
    queue_data: vkt.QueueData,
    p_wait_semaphores: ?[*]const vk.Semaphore,
    wait_semaphore_count: u32,
    image_index: u32,
    g_command_pool: *?vk.CommandPool,
    g_descriptor_set: *?vk.DescriptorSet,
    g_font_already_uploaded: *bool,
    g_font_image: *?vk.Image,
    g_framebuffers: *vkt.FramebufferBacking,
    g_graphic_queue: *?vkt.QueueData,
    g_height: *?u32,
    g_images: *vkt.ImageBacking,
    g_pipeline_layout: *?vk.PipelineLayout,
    g_pipeline: *?vk.Pipeline,
    g_previous_draw_data: *?vkt.DrawData,
    g_render_pass: *?vk.RenderPass,
    g_upload_font_buffer_mem: *?vk.DeviceMemory,
    g_upload_font_buffer: *?vk.Buffer,
    g_width: *?u32,
)
?vkt.DrawData
{
    const imgui_draw_data = imgui_holder.get_draw_data();
    if (imgui_draw_data.total_vtx_count < 1) return null;
    const imgui_cmd_lists_count: u32 = @intCast(imgui_draw_data.cmd_lists_count);

    var draw_data = get_overlay_draw(device, device_wrapper, init_wrapper, g_command_pool, g_previous_draw_data);

    device_wrapper.resetCommandBuffer(draw_data.command_buffer, .{})
    catch @panic("Vulkan function call failed: Device.ResetCommandBuffer");

    const render_pass_info = vk.RenderPassBeginInfo
    {
        .render_pass = g_render_pass.*.?,
        .framebuffer = g_framebuffers.buffer[image_index],
        .render_area = std.mem.zeroInit
        (
            vk.Rect2D,
            .{
                .extent = vk.Extent2D
                {
                    .width = g_width.*.?,
                    .height = g_height.*.?
                }
            },
        ),
    };

    const buffer_begin_info = vk.CommandBufferBeginInfo{};
    device_wrapper.beginCommandBuffer(draw_data.command_buffer, &buffer_begin_info)
    catch @panic("Vulkan function call failed: Device.BeginCommandBuffer");

    ensure_swapchain_fonts
    (
        device,
        draw_data.command_buffer,
        device_wrapper,
        g_font_already_uploaded,
        g_font_image,
        g_upload_font_buffer_mem,
        g_upload_font_buffer,
    );

    {
        const imb_container = [1]vk.ImageMemoryBarrier
        {
            vk.ImageMemoryBarrier
            {
                .src_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true, },
                .dst_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true, },
                .old_layout = .present_src_khr,
                .new_layout = .color_attachment_optimal,
                .src_queue_family_index = queue_data.queue_family_index,
                .dst_queue_family_index = g_graphic_queue.*.?.queue_family_index,
                .image = g_images.get(image_index),
                .subresource_range = vk.ImageSubresourceRange
                {
                    .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
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
            vk.PipelineStageFlags{ .all_graphics_bit = true, },
            vk.PipelineStageFlags{ .all_graphics_bit = true, },
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

    const vertex_size: u64 = @as(u64, @intCast(imgui_draw_data.total_vtx_count)) * imgui_holder.DrawVertSize;
    const index_size: u64 = @as(u64, @intCast(imgui_draw_data.total_idx_count)) * imgui_holder.DrawIdxSize;

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
            vk.BufferUsageFlags{ .vertex_buffer_bit = true, },
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
            vk.BufferUsageFlags{ .index_buffer_bit = true, },
        );
    }

    var vertex_dst: [*]imgui_holder.DrawVert = @ptrCast
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

    var index_dst: [*]imgui_holder.DrawIdx = @ptrCast
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

    for (imgui_draw_data.cmd_lists[0..imgui_cmd_lists_count]) |cmd_list|
    {
        const vertex_buf = imgui_holder.get_draw_list_vertex_buffer(cmd_list);
        const index_buf = imgui_holder.get_draw_list_index_buffer(cmd_list);
        @memcpy(vertex_dst[0..vertex_buf.len], vertex_buf);
        @memcpy(index_dst[0..index_buf.len], index_buf);
        vertex_dst += vertex_buf.len;
        index_dst += index_buf.len;
    }

    const range = [2]vk.MappedMemoryRange
    {
        std.mem.zeroInit
        (
            vk.MappedMemoryRange,
            .{
                .memory = draw_data.vertex_buffer_mem,
                .size = vk.WHOLE_SIZE,
            },
        ),
        std.mem.zeroInit
        (
            vk.MappedMemoryRange,
            .{
                .memory = draw_data.index_buffer_mem,
                .size = vk.WHOLE_SIZE,
            },
        ),
    };

    device_wrapper.flushMappedMemoryRanges(device, 2, &range)
    catch @panic("Vulkan function call failed: Device.FlushMappedMemoryRanges");
    device_wrapper.unmapMemory(device, draw_data.vertex_buffer_mem);
    device_wrapper.unmapMemory(device, draw_data.index_buffer_mem);

    device_wrapper.cmdBindPipeline(draw_data.command_buffer, .graphics, g_pipeline.*.?);
    const desc_set_container = [1]vk.DescriptorSet
    {
        g_descriptor_set.*.?,
    };
    device_wrapper.cmdBindDescriptorSets
    (
        draw_data.command_buffer,
        .graphics,
        g_pipeline_layout.*.?,
        0,
        1,
        &desc_set_container,
        0,
        null,
    );

    const vertex_buffers_container = [1]vk.Buffer
    {
        draw_data.vertex_buffer,
    };
    const vertex_offset_container = [1]vk.DeviceSize
    {
        0,
    };
    device_wrapper.cmdBindVertexBuffers
    (
        draw_data.command_buffer,
        0,
        1,
        &vertex_buffers_container,
        &vertex_offset_container,
    );
    device_wrapper.cmdBindIndexBuffer(draw_data.command_buffer, draw_data.index_buffer, 0, .uint16);

    const viewport_container = [1]vk.Viewport
    {
        vk.Viewport
        {
            .x = 0,
            .y = 0,
            .width = imgui_draw_data.display_size[0],
            .height = imgui_draw_data.display_size[1],
            .min_depth = 0.0,
            .max_depth = 1.0,
        },
    };
    device_wrapper.cmdSetViewport(draw_data.command_buffer, 0, 1, &viewport_container);

    const scale = [2]f32
    {
        2.0 / imgui_draw_data.display_size[0], // x
        2.0 / imgui_draw_data.display_size[1], // y
    };
    device_wrapper.cmdPushConstants
    (
        draw_data.command_buffer,
        g_pipeline_layout.*.?,
        vk.ShaderStageFlags{ .vertex_bit = true, },
        @sizeOf(f32) * 0, // can't this just be 0?
        @sizeOf(f32) * 2,
        std.mem.asBytes(&scale),
    );

    const translate = [2]f32
    {
        -1.0 - imgui_draw_data.display_size[0] * scale[0], // x
        -1.0 - imgui_draw_data.display_size[1] * scale[1], // y
    };
    device_wrapper.cmdPushConstants
    (
        draw_data.command_buffer,
        g_pipeline_layout.*.?,
        vk.ShaderStageFlags{ .vertex_bit = true, },
        @sizeOf(f32) * 2,
        @sizeOf(f32) * 2,
        std.mem.asBytes(&translate),
    );

    {
        var vertex_offset: u32 = 0;
        var index_offset: u32 = 0;
        for (imgui_draw_data.cmd_lists[0..imgui_cmd_lists_count]) |cmd_list|
        {
            for (imgui_holder.get_draw_list_command_buffer(cmd_list)) |cmd|
            {
                const x_pos: i32 = @intFromFloat(cmd.clip_rect[0] - imgui_draw_data.display_pos[0]);
                                                // cmd.clip_rect.x - imgui_draw_data.display_pos.x
                const y_pos: i32 = @intFromFloat(cmd.clip_rect[1] - imgui_draw_data.display_pos[1]);
                                                // cmd.clip_rect.y - imgui_draw_data.display_pos.y
                const scissor = [1]vk.Rect2D
                {
                    vk.Rect2D
                    {
                        .offset = vk.Offset2D
                        {
                            .x = if (x_pos > 0) x_pos else 0,
                            .y = if (y_pos > 0) y_pos else 0,
                        },
                        .extent = vk.Extent2D
                        {
                            .width = @intFromFloat
                            (
                                cmd.clip_rect[2] - cmd.clip_rect[0]
                            ), // cmd.clip_rect.z - cmd.clip_rect.x
                            .height = @intFromFloat
                            (
                                cmd.clip_rect[3] - cmd.clip_rect[1] + 1.0
                            ), // cmd.clip_rect.w - cmd.clip_rect.y + 1
                        },
                    },
                };
                device_wrapper.cmdSetScissor(draw_data.command_buffer, 0, 1, &scissor);

                device_wrapper.cmdDrawIndexed
                (
                    draw_data.command_buffer,
                    cmd.elem_count,
                    1,
                    index_offset,
                    @intCast(vertex_offset),
                    0,
                );

                index_offset += cmd.elem_count;
            }

            vertex_offset += @intCast(imgui_holder.get_draw_list_vertex_buffer(cmd_list).len);
        }
    }

    device_wrapper.cmdEndRenderPass(draw_data.command_buffer);

    if (queue_data.queue_family_index != g_graphic_queue.*.?.queue_family_index)
    {
        const imb_container = [1]vk.ImageMemoryBarrier
        {
            vk.ImageMemoryBarrier
            {
                .src_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true, },
                .dst_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true, },
                .old_layout = .present_src_khr,
                .new_layout = .present_src_khr,
                .src_queue_family_index = g_graphic_queue.*.?.queue_family_index,
                .dst_queue_family_index = queue_data.queue_family_index,
                .image = g_images.get(image_index),
                .subresource_range = vk.ImageSubresourceRange
                {
                    .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
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
            vk.PipelineStageFlags{ .all_graphics_bit = true, },
            vk.PipelineStageFlags{ .all_graphics_bit = true, },
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

    if (wait_semaphore_count == 0 and queue_data.queue != g_graphic_queue.*.?.queue)
    {
        const stages_wait_container = [1]vk.PipelineStageFlags
        {
            vk.PipelineStageFlags{ .all_commands_bit = true, },
        };
        const ce_semaphore_container = [1]vk.Semaphore
        {
            draw_data.cross_engine_semaphore,
        };
        const submit_info_container1 = [1]vk.SubmitInfo
        {
            vk.SubmitInfo
            {
                .wait_semaphore_count = 0,
                .p_wait_dst_stage_mask = &stages_wait_container,
                .command_buffer_count = 0,
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &ce_semaphore_container,
            },
        };

        device_wrapper.queueSubmit(queue_data.queue, 1, &submit_info_container1, .null_handle)
        catch @panic("Vulkan function call failed: Device.QueueSubmit 1");

        const command_buf_container = [1]vk.CommandBuffer
        {
            draw_data.command_buffer,
        };
        const semaphore_container = [1]vk.Semaphore
        {
            draw_data.semaphore,
        };
        const submit_info_container2 = [1]vk.SubmitInfo
        {
            vk.SubmitInfo
            {
                .wait_semaphore_count = 1,
                .p_wait_semaphores = &ce_semaphore_container,
                .p_wait_dst_stage_mask = &stages_wait_container,
                .command_buffer_count = 1,
                .p_command_buffers = &command_buf_container,
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &semaphore_container,
            },
        };

        device_wrapper.queueSubmit(g_graphic_queue.*.?.queue, 1, &submit_info_container2, draw_data.fence)
        catch @panic("Vulkan function call failed: Device.QueueSubmit 2");
    }
    else
    {
        var stages_wait_backing = vkt.PipelineStageFlagsBacking.init(0)
        catch @panic("Failed to get backing buffer for PipelineStageFlags");
        stages_wait_backing.resize(wait_semaphore_count) catch @panic("PipelineStageFlags buffer overflow");

        {
            var i: u32 = 0;
            while (i < wait_semaphore_count) : (i += 1)
            {
                stages_wait_backing.buffer[i] = vk.PipelineStageFlags{ .fragment_shader_bit = true, };
            }
        }

        const command_buf_container = [1]vk.CommandBuffer
        {
            draw_data.command_buffer,
        };
        const semaphore_container = [1]vk.Semaphore
        {
            draw_data.semaphore,
        };
        const submit_info_container = [1]vk.SubmitInfo
        {
            vk.SubmitInfo
            {
                .wait_semaphore_count = wait_semaphore_count,
                .p_wait_semaphores = p_wait_semaphores,
                .p_wait_dst_stage_mask = stages_wait_backing.constSlice().ptr,
                .command_buffer_count = 1,
                .p_command_buffers = &command_buf_container,
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &semaphore_container,
            },
        };

        device_wrapper.queueSubmit(g_graphic_queue.*.?.queue, 1, &submit_info_container, draw_data.fence)
        catch @panic("Vulkan function call failed: Device.QueueSubmit");
    }

    return draw_data;
}

pub fn before_present
(
    device: vk.Device,
    device_wrapper: vkt.LayerDeviceWrapper,
    init_wrapper: vkl.LayerInitWrapper,
    queue_data: vkt.QueueData,
    p_wait_semaphores: ?[*]const vk.Semaphore,
    wait_semaphore_count: u32,
    image_index: u32,
    g_command_pool: *?vk.CommandPool,
    g_descriptor_set: *?vk.DescriptorSet,
    g_font_already_uploaded: *bool,
    g_font_image: *?vk.Image,
    g_framebuffers: *vkt.FramebufferBacking,
    g_graphic_queue: *?vkt.QueueData,
    g_height: *?u32,
    g_image_count: *?u32,
    g_images: *vkt.ImageBacking,
    g_pipeline_layout: *?vk.PipelineLayout,
    g_pipeline: *?vk.Pipeline,
    g_previous_draw_data: *?vkt.DrawData,
    g_render_pass: *?vk.RenderPass,
    g_upload_font_buffer_mem: *?vk.DeviceMemory,
    g_upload_font_buffer: *?vk.Buffer,
    g_width: *?u32,
)
?vkt.DrawData
{
    if (g_image_count.*.? > 0)
    {
        imgui_holder.draw_frame();
        return render_swapchain_display
        (
            device,
            device_wrapper,
            init_wrapper,
            queue_data,
            p_wait_semaphores,
            wait_semaphore_count,
            image_index,
            g_command_pool,
            g_descriptor_set,
            g_font_already_uploaded,
            g_font_image,
            g_framebuffers,
            g_graphic_queue,
            g_height,
            g_images,
            g_pipeline_layout,
            g_pipeline,
            g_previous_draw_data,
            g_render_pass,
            g_upload_font_buffer_mem,
            g_upload_font_buffer,
            g_width,
        );
    }

    return null;
}
