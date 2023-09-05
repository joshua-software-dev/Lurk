const builtin = @import("builtin");
const std = @import("std");

const disc = @import("discord_conn_holder.zig");
const setup = @import("setup/vk_setup.zig");
const vk_global_state = @import("setup/vk_global_state.zig");
const vk_setup_wrappers = @import("setup/vk_setup_wrappers.zig");
const vkt = @import("setup/vk_types.zig");

const vk = @import("vk.zig");


// Zig scoped logger set based on compile mode
pub const std_options = struct
{
    pub const log_scope_levels: []const std.log.ScopeLevel =
    &[_]std.log.ScopeLevel
    {
        .{
            .scope = .VKLURK,
            .level = switch (builtin.mode)
            {
                .Debug => .debug,
                else => .info,
            }
        },
        .{
            .scope = .WS,
            .level = switch (builtin.mode)
            {
                .Debug => .debug,
                else => .info,
            }
        },
    };
};


///////////////////////////////////////////////////////////////////////////////
// Layer globals definition

// Give this layer a unique name
const LAYER_NAME = "VK_LAYER_Lurk_" ++ switch (builtin.cpu.arch)
{
    .x86 => "x86_32",
    .x86_64 => "x86_64",
    else => @panic("Unsupported CPU architecture"),
};
const LAYER_DESC =
    "Lurk as a Vulkan Layer - " ++
    "https://github.com/joshua-software-dev/Lurk";

///////////////////////////////////////////////////////////////////////////////
// Layer init and shutdown

export fn VkLayerLurk_CreateInstance
(
    p_create_info: *const vk.InstanceCreateInfo,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_instance: *vk.Instance
)
callconv(vk.vulkan_call_conv) vk.Result
{
    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Create Instance: " ++ LAYER_NAME, .{});

    const instance_data = vk_setup_wrappers.create_instance_wrappers(p_create_info, p_allocator, p_instance);
    if (instance_data != null)
    {
        const instance = p_instance.*;
        for (setup.map_physical_devices_to_instance(instance, instance_data.?.instance_wrapper)) |physical_device|
        {
            vk_global_state.physical_device_backing.put(physical_device, instance) catch @panic("oom");
        }

        return vk.Result.success;
    }

    return vk.Result.error_initialization_failed;
}

export fn VkLayerLurk_DestroyInstance
(
    instance: vk.Instance,
    p_allocator: ?*const vk.AllocationCallbacks
)
callconv(vk.vulkan_call_conv) void
{
    _ = p_allocator;
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Destroy Instance: " ++ LAYER_NAME, .{});

    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();

    var instance_data = vk_global_state.instance_backing.fetchRemove(instance).?;
    if (vk_global_state.instance_backing.count() == 0) disc.stop_discord_conn();

    setup.destroy_instance(instance, instance_data.value.instance_wrapper);
}

export fn VkLayerLurk_CreateDevice
(
    physical_device: vk.PhysicalDevice,
    p_create_info: *const vk.DeviceCreateInfo,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_device: *vk.Device
)
callconv(vk.vulkan_call_conv) vk.Result
{
    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Create Device: " ++ LAYER_NAME, .{});

    var device_data = vk_setup_wrappers.create_device_wrappers(physical_device, p_create_info, p_allocator, p_device);
    const instance = vk_global_state.physical_device_backing.get(physical_device).?;
    const instance_data: vkt.InstanceData = vk_global_state.instance_backing.get(instance).?;

    setup.get_physical_mem_props(physical_device, instance_data.instance_wrapper);
    setup.device_map_queues
    (
        p_create_info,
        physical_device,
        device_data.device,
        device_data.set_device_loader_data_func,
        instance_data.instance_wrapper,
        device_data.device_wrapper,
        &vk_global_state.queue_backing,
        &device_data.graphic_queue,
    );

    return vk.Result.success;
}

export fn VkLayerLurk_DestroyDevice
(
    device: vk.Device,
    p_allocator: ?*const vk.AllocationCallbacks
)
callconv(vk.vulkan_call_conv) void
{
    _ = p_allocator;
    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Destroy Device: " ++ LAYER_NAME, .{});

    _ = vk_global_state.device_backing.remove(device);
}

///////////////////////////////////////////////////////////////////////////////
// Actual layer implementation

export fn VkLayerLurk_CreateSwapchainKHR
(
    device: vk.Device,
    p_create_info: *const vk.SwapchainCreateInfoKHR,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_swapchain: *vk.SwapchainKHR,
)
callconv(vk.vulkan_call_conv) vk.Result
{
    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Create Swapchain: " ++ LAYER_NAME, .{});
    var device_data: *vkt.DeviceData = vk_global_state.device_backing.getPtr(device).?;

    const result = device_data.device_wrapper.dispatch.vkCreateSwapchainKHR
    (
        device,
        p_create_info,
        p_allocator,
        p_swapchain,
    );
    if (result != vk.Result.success) return result;

    const swapchain = p_swapchain.*;
    const backing = vk_global_state.swapchain_backing.getOrPut(swapchain) catch @panic("oom");
    if (backing.found_existing)
    {
        setup.destroy_swapchain
        (
            device,
            device_data.device_wrapper,
            backing.value_ptr,
            &device_data.previous_draw_data,
        );
    }
    backing.value_ptr.* = vkt.SwapchainData
    {
        .command_pool = null,
        .descriptor_layout = null,
        .descriptor_pool = null,
        .descriptor_set = null,
        .device = device,
        .font_image_view = null,
        .font_image = null,
        .font_mem = null,
        .font_sampler = null,
        .font_uploaded = false,
        .format = null,
        .height = null,
        .image_count = null,
        .imgui_context = null,
        .pipeline_layout = null,
        .pipeline = null,
        .render_pass = null,
        .swapchain = p_swapchain.*,
        .upload_font_buffer_mem = null,
        .upload_font_buffer = null,
        .width = null,
        .framebuffers = vkt.FramebufferBacking.init(0) catch @panic("oom"),
        .image_views = vkt.ImageViewBacking.init(0) catch @panic("oom"),
        .images = vkt.ImageBacking.init(0) catch @panic("oom"),
    };

    setup.setup_swapchain
    (
        device,
        device_data.device_wrapper,
        p_create_info,
        backing.value_ptr,
        &device_data.graphic_queue,
    );

    return result;
}

export fn VkLayerLurk_DestroySwapchainKHR
(
    device: vk.Device,
    swapchain: vk.SwapchainKHR,
    p_allocator: ?*const vk.AllocationCallbacks,
)
callconv(vk.vulkan_call_conv) void
{
    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Destroy Swapchain: " ++ LAYER_NAME, .{});

    if (swapchain == .null_handle)
    {
        var device_data: vkt.DeviceData = vk_global_state.device_backing.get(device).?;
        device_data.device_wrapper.destroySwapchainKHR(device, swapchain, p_allocator);
        return;
    }

    var swapchain_data = vk_global_state.swapchain_backing.fetchRemove(swapchain).?;
    var device_data: *vkt.DeviceData = vk_global_state.device_backing.getPtr(swapchain_data.value.device).?;
    setup.destroy_swapchain
    (
        device,
        device_data.device_wrapper,
        @constCast(&swapchain_data.value),
        &device_data.previous_draw_data,
    );
    device_data.device_wrapper.destroySwapchainKHR(device, swapchain, p_allocator);
}

export fn VkLayerLurk_QueuePresentKHR
(
    queue: vk.Queue,
    p_present_info: *const vk.PresentInfoKHR,
)
callconv(vk.vulkan_call_conv) vk.Result
{
    var final_result = vk.Result.success;

    {
        vk_global_state.wrappers_global_lock.lock();
        defer vk_global_state.wrappers_global_lock.unlock();
        var queue_data: *vkt.VkQueueData = vk_global_state.queue_backing.getPtr(queue).?;
        var device_data: *vkt.DeviceData = vk_global_state.device_backing.getPtr(queue_data.device).?;

        setup.wait_before_queue_present
        (
            device_data.device,
            device_data.device_wrapper,
            queue,
            queue_data,
        );

        {
            disc.output_lock.lock();
            defer disc.output_lock.unlock();

            var i: u32 = 0;
            while (i < p_present_info.swapchain_count) : (i += 1)
            {
                var swapchain_data: ?*vkt.SwapchainData = vk_global_state.swapchain_backing.getPtr
                (
                    p_present_info.p_swapchains[i],
                );

                if (swapchain_data == null or swapchain_data.?.device != queue_data.device)
                {
                    final_result = vk.Result.error_unknown;
                    continue;
                }

                const maybe_draw_data = setup.before_present
                (
                    device_data.device,
                    device_data.set_device_loader_data_func,
                    device_data.device_wrapper,
                    queue_data,
                    p_present_info.p_wait_semaphores,
                    p_present_info.wait_semaphore_count,
                    p_present_info.p_image_indices[i],
                    &device_data.graphic_queue,
                    &device_data.previous_draw_data,
                    swapchain_data.?,
                    disc.output_label,
                );

                var present_info = p_present_info.*;
                if (maybe_draw_data) |draw_data|
                {
                    const semaphore_container = [1]vk.Semaphore
                    {
                        draw_data.semaphore,
                    };
                    present_info.p_wait_semaphores = &semaphore_container;
                    present_info.wait_semaphore_count = 1;
                }

                const chain_result = device_data.device_wrapper.dispatch.vkQueuePresentKHR
                (
                    queue,
                    &present_info,
                );

                if (p_present_info.p_results) |p_results|
                {
                    p_results[i] = chain_result;
                }

                if (chain_result != vk.Result.success and final_result == vk.Result.success)
                {
                    final_result = chain_result;
                }
            }
        }
    }

    return final_result;
}

export fn VkLayerLurk_GetDeviceProcAddr
(
    device: vk.Device,
    p_name: [*:0]const u8
)
callconv(vk.vulkan_call_conv) vk.PfnVoidFunction
{
    const span_name = std.mem.span(p_name);

    // device chain functions we intercept
    if (std.mem.eql(u8, span_name, "vkGetDeviceProcAddr"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_GetDeviceProcAddr));
    }
    else if (std.mem.eql(u8, span_name, "vkCreateDevice"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CreateDevice));
    }
    else if (std.mem.eql(u8, span_name, "vkDestroyDevice"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_DestroyDevice));
    }
    else if (std.mem.eql(u8, span_name, "vkCreateSwapchainKHR"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CreateSwapchainKHR));
    }
    else if (std.mem.eql(u8, span_name, "vkDestroySwapchainKHR"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_DestroySwapchainKHR));
    }
    else if (std.mem.eql(u8, span_name, "vkQueuePresentKHR"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_QueuePresentKHR));
    }

    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    const device_data: vkt.DeviceData = vk_global_state.device_backing.get(device).?;
    return @ptrCast(@alignCast(device_data.get_device_proc_addr_func(device, p_name)));
}

export fn VkLayerLurk_GetInstanceProcAddr
(
    instance: vk.Instance,
    p_name: [*:0]const u8
)
callconv(vk.vulkan_call_conv) vk.PfnVoidFunction
{
    // Internal logic makes connecting multiple times idempotent
    disc.start_discord_conn(std.heap.c_allocator) catch @panic("Failed to start discord connection.");

    const span_name = std.mem.span(p_name);

    // instance chain functions we intercept
    if (std.mem.eql(u8, span_name, "vkGetInstanceProcAddr"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_GetInstanceProcAddr));
    }
    else if (std.mem.eql(u8, span_name, "vkCreateInstance"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CreateInstance));
    }
    else if (std.mem.eql(u8, span_name, "vkDestroyInstance"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_DestroyInstance));
    }

    // device chain functions we intercept
    if (std.mem.eql(u8, span_name, "vkGetDeviceProcAddr"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_GetDeviceProcAddr));
    }
    else if (std.mem.eql(u8, span_name, "vkCreateDevice"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CreateDevice));
    }
    else if (std.mem.eql(u8, span_name, "vkDestroyDevice"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_DestroyDevice));
    }
    else if (std.mem.eql(u8, span_name, "vkCreateSwapchainKHR"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CreateSwapchainKHR));
    }
    else if (std.mem.eql(u8, span_name, "vkDestroySwapchainKHR"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_DestroySwapchainKHR));
    }
    else if (std.mem.eql(u8, span_name, "vkQueuePresentKHR"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_QueuePresentKHR));
    }

    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    const instance_data: vkt.InstanceData = vk_global_state.instance_backing.get(instance).?;
    return @ptrCast(@alignCast(instance_data.base_wrapper.getInstanceProcAddr(instance, p_name)));
}
