const std = @import("std");

const vk = @import("vulkan-zig");
const vk_layer_stubs = @import("vk_layer_stubs.zig");
const zgui = @import("zgui");


var current_imgui_context: ?zgui.Context = null;
var height: ?f32 = null;
var width: ?f32 = null;
var format: ?vk.Format = null;
var render_pass: vk.RenderPass = std.mem.zeroes(vk.RenderPass);


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
            .samples = vk.SampleCountFlags{ .@"1_bit" = true },
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
