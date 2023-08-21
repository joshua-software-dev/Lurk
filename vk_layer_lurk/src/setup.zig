const std = @import("std");

const embedded_shaders = @import("embedded_shaders.zig");

const vk = @import("vk.zig");
const vk_layer_stubs = @import("vk_layer_stubs.zig");
const zgui = @import("zgui");



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

var pipeline_container: [1]vk.Pipeline = [1]vk.Pipeline
{
    std.mem.zeroes(vk.Pipeline),
};
var pipeline: *vk.Pipeline = &pipeline_container[0];

var current_imgui_context: ?zgui.Context = null;
var descriptor_pool: vk.DescriptorPool = std.mem.zeroes(vk.DescriptorPool);
var font_image_view: vk.ImageView = std.mem.zeroes(vk.ImageView);
var font_image: vk.Image = std.mem.zeroes(vk.Image);
var font_mem: vk.DeviceMemory = std.mem.zeroes(vk.DeviceMemory);
var font_sampler: vk.Sampler = std.mem.zeroes(vk.Sampler);
var format: ?vk.Format = null;
var height: ?f32 = null;
var physical_mem_props: ?vk.PhysicalDeviceMemoryProperties = null;
var pipeline_layout: vk.PipelineLayout = std.mem.zeroes(vk.PipelineLayout);
var render_pass: vk.RenderPass = std.mem.zeroes(vk.RenderPass);
var width: ?f32 = null;


fn vk_memory_type(properties: vk.MemoryPropertyFlags, type_bits: u32) u32
{
    _ = type_bits;
    if (physical_mem_props) |props|
    {
        var i: u32 = 0;
        while (i < props.memory_type_count) : (i += 1)
        {
            if
            (
                vk.MemoryPropertyFlags.contains(properties, props.memory_types[i].property_flags)
                // and type_bits & (1<<i)
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
    var frag_module: vk.ShaderModule = std.mem.zeroes(vk.ShaderModule);
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

    var vert_module: vk.ShaderModule = std.mem.zeroes(vk.ShaderModule);
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
    device_dispatcher.DestroyShaderModule(device, vert_module, null);

    // Font sampler
    const font_sampler_info = vk.SamplerCreateInfo
    {
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .min_lod = -1000,
        .max_lod = 1000,
        .max_anisotropy = 1,
        // equivalent of zero init
        .mip_lod_bias = 0,
        .anisotropy_enable = 0,
        .compare_enable = 0,
        .compare_op = .never,
        .border_color = .float_transparent_black,
        .unnormalized_coordinates = 0,
    };
    const font_sampler_result = device_dispatcher.CreateSampler(device, &font_sampler_info, null, &font_sampler);
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

    const sampler = [1]vk.Sampler
    {
        font_sampler
    };
    const binding = [1]vk.DescriptorSetLayoutBinding
    {
        vk.DescriptorSetLayoutBinding
        {
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = vk.ShaderStageFlags{ .fragment_bit = true, },
            .p_immutable_samplers = &sampler,
            // 0 init equivalents
            .binding = 0,
        },
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
        vk.VertexInputBindingDescription
        {
            .input_rate = .vertex,
            .stride = @sizeOf(zgui.DrawVert),
            // 0 init equivalents
            .binding = 0,
        },
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

    const ia_info = vk.PipelineInputAssemblyStateCreateInfo
    {
        .topology = .triangle_list,
        // 0 init equivalents
        .primitive_restart_enable = 0,
    };

    const viewport_info = vk.PipelineViewportStateCreateInfo
    {
        .viewport_count = 1,
        .scissor_count = 1,
    };

    const raster_info = vk.PipelineRasterizationStateCreateInfo
    {
        .polygon_mode = .fill,
        .cull_mode = .{},
        .front_face = .counter_clockwise,
        .line_width = 1.0,
        // 0 init equivalents
        .depth_clamp_enable = 0,
        .rasterizer_discard_enable = 0,
        .depth_bias_enable = 0,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
    };

    const ms_info = vk.PipelineMultisampleStateCreateInfo
    {
        .rasterization_samples = vk.SampleCountFlags{ .@"1_bit" = true, },
        // 0 init equivalents
        .sample_shading_enable = 0,
        .min_sample_shading = 0,
        .alpha_to_coverage_enable = 0,
        .alpha_to_one_enable = 0,
    };

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
            .color_write_mask = vk.ColorComponentFlags{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true, },
        },
    };

    const depth_info = std.mem.zeroInit(vk.PipelineDepthStencilStateCreateInfo, .{});

    const blend_info = vk.PipelineColorBlendStateCreateInfo
    {
        .attachment_count = 1,
        .p_attachments = &color_attachment,
        // 0 init equivalents
        .logic_op_enable = 0,
        .logic_op = .clear,
        .blend_constants = std.mem.zeroes([4]f32),
    };

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
        vk.GraphicsPipelineCreateInfo
        {
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
            // 0 init equivalents
            .subpass = 0,
            .base_pipeline_index = 0,
        }
    };
    _ = info_container;
    // const create_pl_result = device_dispatcher.CreateGraphicsPipelines
    // (
    //     device,
    //     .null_handle,
    //     1,
    //     &info_container,
    //     null,
    //     &pipeline_container
    // );
    // if (create_pl_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateGraphicsPipelines");

    _ = device_dispatcher.DestroyShaderModule(device, vert_module, null);
    _ = device_dispatcher.DestroyShaderModule(device, frag_module, null);

    var h: i32 = 0;
    var w: i32 = 0;
    _ = zgui.io.getFontsTextDataAsRgba32(&h, &w);
    if (h < 1 or w < 1) @panic("ImGui provided an invalid font size.");

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

    var font_image_req: vk.MemoryRequirements = std.mem.zeroes(vk.MemoryRequirements);
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

    const view_info = vk.ImageViewCreateInfo
    {
        .image = font_image,
        .view_type = .@"2d",
        .format = .r8g8b8a8_unorm,
        .subresource_range = vk.ImageSubresourceRange
        {
            .aspect_mask = vk.ImageAspectFlags{ .color_bit = true, },
            .level_count = 1,
            .layer_count = 1,
            // 0 init equivalents
            .base_mip_level = 0,
            .base_array_layer = 0,
        },
        // 0 init equivalent
        .components = std.mem.zeroes(vk.ComponentMapping),
    };
    const create_view_result = device_dispatcher.CreateImageView(device, &view_info, null, &font_image_view);
    if (create_view_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateImageView");

    const desc_image = [1]vk.DescriptorImageInfo
    {
        vk.DescriptorImageInfo
        {
            .sampler = font_sampler,
            .image_view = font_image_view,
            .image_layout = .shader_read_only_optimal,
        },
    };
    const write_desc = [1]vk.WriteDescriptorSet
    {
        vk.WriteDescriptorSet
        {
            .dst_set = descriptor_set.*,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = &desc_image,
            // 0 init equivalents
            .dst_binding = 0,
            .dst_array_element = 0,
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
    };
    device_dispatcher.UpdateDescriptorSets(device, 1, &write_desc, 0, null);
}

pub fn setup_swapchain
(
    device: vk.Device,
    device_dispatcher: vk_layer_stubs.LayerDispatchTable,
    p_create_info: *const vk.SwapchainCreateInfoKHR
)
void
{
    height = @floatFromInt(p_create_info.image_extent.height);
    width = @floatFromInt(p_create_info.image_extent.width);
    format = p_create_info.image_format;

    current_imgui_context = zgui.zguiCreateContext(null);
    zgui.zguiSetCurrentContext(current_imgui_context);

    zgui.io.setIniFilename(null);
    zgui.io.setDisplaySize(width.?, height.?);

    const attachment_desc: [1]vk.AttachmentDescription =
    .{
        vk.AttachmentDescription
        {
            .format = p_create_info.image_format,
            .samples = vk.SampleCountFlags{ .@"1_bit" = true, },
            .load_op = .load,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .color_attachment_optimal,
            .final_layout = .present_src_khr,
        },
    };

    const color_attachment: [1]vk.AttachmentReference =
    .{
        vk.AttachmentReference
        {
            .attachment = 0,
            .layout = .color_attachment_optimal,
        },
    };

    const subpass: [1]vk.SubpassDescription =
    .{
        vk.SubpassDescription
        {
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &color_attachment,
        },
    };

    const dependency: [1]vk.SubpassDependency =
    .{
        vk.SubpassDependency
        {
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true, },
            .dst_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true, },
            .src_access_mask = vk.AccessFlags.fromInt(0),
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

    const result = device_dispatcher.CreateRenderPass(device, &render_pass_info, null, &render_pass);
    if (result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateRenderPass");

    setup_swapchain_data_pipeline(device, device_dispatcher);
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
    instance_dispatcher: vk_layer_stubs.LayerInstanceDispatchTable
)
void
{
    physical_mem_props = std.mem.zeroes(vk.PhysicalDeviceMemoryProperties);
    instance_dispatcher.GetPhysicalDeviceMemoryProperties(physical_device, &physical_mem_props.?);
}
