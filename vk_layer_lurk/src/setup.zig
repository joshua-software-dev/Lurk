const std = @import("std");

const embedded_shaders = @import("embedded_shaders.zig");

const vk = @import("vk.zig");
const vk_layer_stubs = @import("vk_layer_stubs.zig");
const zgui = @import("zgui");


var current_imgui_context: ?zgui.Context = null;
var descriptor_layout: vk.DescriptorSetLayout = std.mem.zeroes(vk.DescriptorSetLayout);
var descriptor_pool: vk.DescriptorPool = std.mem.zeroes(vk.DescriptorPool);
var font_sampler: vk.Sampler = std.mem.zeroes(vk.Sampler);
var format: ?vk.Format = null;
var height: ?f32 = null;
var render_pass: vk.RenderPass = std.mem.zeroes(vk.RenderPass);
var width: ?f32 = null;

fn setup_swapchain_data_pipeline(device: vk.Device, device_dispatcher: vk_layer_stubs.LayerDispatchTable) void
{
    // Create shader modules
    var frag_module: vk.ShaderModule = std.mem.zeroes(vk.ShaderModule);
    const frag_info = vk.ShaderModuleCreateInfo
    {
        .s_type = vk.StructureType.shader_module_create_info,
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
        .s_type = vk.StructureType.shader_module_create_info,
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
        .s_type = vk.StructureType.sampler_create_info,
        .mag_filter = vk.Filter.linear,
        .min_filter = vk.Filter.linear,
        .mipmap_mode = vk.SamplerMipmapMode.linear,
        .address_mode_u = vk.SamplerAddressMode.repeat,
        .address_mode_v = vk.SamplerAddressMode.repeat,
        .address_mode_w = vk.SamplerAddressMode.repeat,
        .min_lod = -1000,
        .max_lod = 1000,
        .max_anisotropy = 1,
        // equivalent of zero init
        .mip_lod_bias = 0,
        .anisotropy_enable = 0,
        .compare_enable = 0,
        .compare_op = vk.CompareOp.never,
        .border_color = vk.BorderColor.float_transparent_black,
        .unnormalized_coordinates = 0,
    };
    const font_sampler_result = device_dispatcher.CreateSampler(device, &font_sampler_info, null, &font_sampler);
    if (font_sampler_result != vk.Result.success) @panic("Vulkan function call failed: Device.CreateSampler");

    // Descriptor pool
    const sampler_pool_size = [1]vk.DescriptorPoolSize
    {
        vk.DescriptorPoolSize
        {
            .type = vk.DescriptorType.combined_image_sampler,
            .descriptor_count = 1,
        },
    };
    const desc_pool_info = vk.DescriptorPoolCreateInfo
    {
        .s_type = vk.StructureType.descriptor_pool_create_info,
        .max_sets = 1,
        .pool_size_count = 1,
        .p_pool_sizes = sampler_pool_size[0..0].ptr,
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
            .descriptor_type = vk.DescriptorType.combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = vk.ShaderStageFlags{ .fragment_bit = true, },
            .p_immutable_samplers = sampler[0..0].ptr,
            .binding = 0,
        }
    };
    const set_layout_info = vk.DescriptorSetLayoutCreateInfo
    {
        .s_type = vk.StructureType.descriptor_set_layout_create_info,
        .binding_count = 1,
        .p_bindings = binding[0..0].ptr,
    };

    const desc_layout_result = device_dispatcher.CreateDescriptorSetLayout
    (
        device,
        &set_layout_info,
        null,
        &descriptor_layout
    );
    if (desc_layout_result != vk.Result.success)
    {
        @panic("Vulkan function call failed: Device.CreateDescriptorSetLayout");
    }
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
            .load_op = vk.AttachmentLoadOp.load,
            .store_op = vk.AttachmentStoreOp.store,
            .stencil_load_op = vk.AttachmentLoadOp.dont_care,
            .stencil_store_op = vk.AttachmentStoreOp.dont_care,
            .initial_layout = vk.ImageLayout.color_attachment_optimal,
            .final_layout = vk.ImageLayout.present_src_khr,
        },
    };

    const color_attachment: [1]vk.AttachmentReference =
    .{
        vk.AttachmentReference
        {
            .attachment = 0,
            .layout = vk.ImageLayout.color_attachment_optimal,
        },
    };

    const subpass: [1]vk.SubpassDescription =
    .{
        vk.SubpassDescription
        {
            .pipeline_bind_point = vk.PipelineBindPoint.graphics,
            .color_attachment_count = 1,
            .p_color_attachments = color_attachment[0..0].ptr,
        },
    };

    const dependency: [1]vk.SubpassDependency =
    .{
        vk.SubpassDependency
        {
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true },
            .dst_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true },
            .src_access_mask = vk.AccessFlags.fromInt(0),
            .dst_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true },
        },
    };

    const render_pass_info = vk.RenderPassCreateInfo
    {
        .s_type = vk.StructureType.render_pass_create_info,
        .attachment_count = 1,
        .p_attachments = attachment_desc[0..0].ptr,
        .subpass_count = 1,
        .p_subpasses = subpass[0..0].ptr,
        .dependency_count = 1,
        .p_dependencies = dependency[0..0].ptr,
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
