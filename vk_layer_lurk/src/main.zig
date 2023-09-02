const builtin = @import("builtin");
const std = @import("std");

const disc = @import("discord_conn_holder.zig");
const setup = @import("setup/vk_setup.zig");
const vk_global_state = @import("setup/vk_global_state.zig");
const vk_setup_wrappers = @import("setup/vk_setup_wrappers.zig");

const vk = @import("vk.zig");


// Zig scoped logger set based on compile mode
pub const std_options = struct
{
    pub const log_scope_levels: []const std.log.ScopeLevel =
    &[_]std.log.ScopeLevel
    {
        .{
            .scope = .LAYER,
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
const LAYER_NAME = "VK_LAYER_Lurk";
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

    vk_setup_wrappers.create_instance_wrappers(p_create_info, p_instance);
    if (vk_global_state.base_wrapper) |base_wrapper|
    {
        return base_wrapper.dispatch.vkCreateInstance(p_create_info, p_allocator, p_instance);
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

    disc.stop_discord_conn();

    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    setup.destroy_instance(instance, vk_global_state.instance_wrapper.?);

    vk_global_state.base_wrapper = null;
    vk_global_state.instance_wrapper = null;
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

    const create_device_result = vk_global_state.instance_wrapper.?.dispatch.vkCreateDevice
    (
        physical_device,
        p_create_info,
        p_allocator,
        p_device,
    );
    if (create_device_result != vk.Result.success) return create_device_result;

    vk_setup_wrappers.create_device_wrappers(p_device, p_create_info);
    vk_global_state.persistent_device = p_device.*;

    setup.get_physical_mem_props(physical_device, vk_global_state.instance_wrapper.?);
    setup.device_map_queues
    (
        p_create_info,
        physical_device,
        p_device.*,
        vk_global_state.device_wrapper.?,
        vk_global_state.init_wrapper.?,
        vk_global_state.instance_wrapper.?,
        &vk_global_state.device_queues,
        &vk_global_state.graphic_queue,
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
    _ = device;
    _ = p_allocator;
    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();

    vk_global_state.device_wrapper = null;
    vk_global_state.init_wrapper = null;
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

    const result = vk_global_state.device_wrapper.?.dispatch.vkCreateSwapchainKHR
    (
        device,
        p_create_info,
        p_allocator,
        p_swapchain,
    );
    if (result != vk.Result.success) return result;

    vk_global_state.swapchain = p_swapchain.*;

    setup.setup_swapchain
    (
        device,
        vk_global_state.device_wrapper.?,
        p_create_info,
        &vk_global_state.command_pool,
        &vk_global_state.descriptor_layout,
        &vk_global_state.descriptor_pool,
        &vk_global_state.descriptor_set,
        &vk_global_state.font_image_view,
        &vk_global_state.font_image,
        &vk_global_state.font_mem,
        &vk_global_state.font_sampler,
        &vk_global_state.format,
        &vk_global_state.framebuffers,
        &vk_global_state.graphic_queue,
        &vk_global_state.height,
        &vk_global_state.image_count,
        &vk_global_state.image_views,
        &vk_global_state.images,
        &vk_global_state.pipeline_layout,
        &vk_global_state.pipeline,
        &vk_global_state.render_pass,
        &vk_global_state.swapchain,
        &vk_global_state.width,
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

    vk_global_state.device_wrapper.?.destroySwapchainKHR(device, swapchain, p_allocator);
    setup.destroy_swapchain(device, vk_global_state.device_wrapper.?, &vk_global_state.render_pass);
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
        const queue_data = setup.wait_before_queue_present
        (
            vk_global_state.persistent_device.?,
            vk_global_state.device_wrapper.?,
            queue,
            &vk_global_state.device_queues,
        );

        {
            var i: u32 = 0;
            while (i < p_present_info.swapchain_count) : (i += 1)
            {
                const maybe_draw_data = setup.before_present
                (
                    vk_global_state.persistent_device.?,
                    vk_global_state.device_wrapper.?,
                    vk_global_state.init_wrapper.?,
                    queue_data,
                    p_present_info.p_wait_semaphores,
                    p_present_info.wait_semaphore_count,
                    p_present_info.p_image_indices[i],
                    &vk_global_state.command_pool,
                    &vk_global_state.descriptor_set,
                    &vk_global_state.font_already_uploaded,
                    &vk_global_state.font_image,
                    &vk_global_state.framebuffers,
                    &vk_global_state.graphic_queue,
                    &vk_global_state.height,
                    &vk_global_state.image_count,
                    &vk_global_state.images,
                    &vk_global_state.pipeline_layout,
                    &vk_global_state.pipeline,
                    &vk_global_state.previous_draw_data,
                    &vk_global_state.render_pass,
                    &vk_global_state.upload_font_buffer_mem,
                    &vk_global_state.upload_font_buffer,
                    &vk_global_state.width,
                );

                var present_info = p_present_info.*;
                if (maybe_draw_data) |draw_data|
                {
                    const semaphore_container = [1]vk.Semaphore
                    {
                        draw_data.semaphore
                    };
                    present_info.p_wait_semaphores = &semaphore_container;
                    present_info.wait_semaphore_count = 1;
                }

                const chain_result = vk_global_state.device_wrapper.?.dispatch.vkQueuePresentKHR(queue, &present_info);

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

///////////////////////////////////////////////////////////////////////////////
// Enumeration functions

export fn VkLayerLurk_EnumerateInstanceLayerProperties
(
    p_property_count: *u32,
    p_properties: ?[*]vk.LayerProperties
)
callconv(vk.vulkan_call_conv) vk.Result
{
    // The c++ implementation checks that this pointer is not null, an
    // unnecessary step as by vulkan convention it must be a valid pointer, so
    // the check is removed here
    p_property_count.* = 1;

    if (p_properties) |props|
    {
        @memcpy
        (
            &props[0].layer_name,
            @as(*[vk.MAX_DESCRIPTION_SIZE]u8, @ptrCast(@constCast(LAYER_NAME)))
        );

        @memcpy
        (
            &props[0].description,
            @as(*[vk.MAX_DESCRIPTION_SIZE]u8, @ptrCast(@constCast(LAYER_DESC)))
        );

        props[0].implementation_version = 1;
        props[0].spec_version = vk.API_VERSION_1_0;
    }

    return vk.Result.success;
}

export fn VkLayerLurk_EnumerateDeviceLayerProperties
(
    physical_device: vk.PhysicalDevice,
    p_property_count: *u32,
    p_properties: ?[*]vk.LayerProperties
)
callconv(vk.vulkan_call_conv) vk.Result
{
    _ = physical_device;
    return VkLayerLurk_EnumerateInstanceLayerProperties(p_property_count, p_properties);
}

export fn VkLayerLurk_EnumerateInstanceExtensionProperties
(
    p_layer_name: ?[*:0]const u8,
    p_property_count: *u32,
    p_properties: ?[*]vk.ExtensionProperties
)
callconv(vk.vulkan_call_conv) vk.Result
{
    _ = p_properties;
    if
    (
        p_layer_name == null or
        !std.mem.eql(u8, std.mem.span(p_layer_name.?), LAYER_NAME)
    )
    {
        return vk.Result.error_layer_not_present;
    }

    // The c++ implementation checks that this pointer is not null, which once
    // again, cannot happen according to the API, and so the check is also
    // removed here
    //
    // don't expose any extensions
    p_property_count.* = 0;
    return vk.Result.success;
}

export fn VkLayerLurk_EnumerateDeviceExtensionProperties
(
    physical_device: vk.PhysicalDevice,
    p_layer_name: ?[*:0]const u8,
    p_property_count: *u32,
    p_properties: ?[*]vk.ExtensionProperties
)
callconv(vk.vulkan_call_conv) vk.Result
{
    // pass through any queries that aren't to us
    if
    (
        p_layer_name == null or
        !std.mem.eql(u8, std.mem.span(p_layer_name.?), LAYER_NAME)
    )
    {
        if (physical_device == vk.PhysicalDevice.null_handle)
        {
            return vk.Result.success;
        }

        vk_global_state.wrappers_global_lock.lock();
        defer vk_global_state.wrappers_global_lock.unlock();
        return vk_global_state.instance_wrapper.?.dispatch.vkEnumerateDeviceExtensionProperties
        (
            physical_device,
            p_layer_name,
            p_property_count,
            p_properties
        );
    }

    // don't expose any extensions
    p_property_count.* = 0;
    return vk.Result.success;
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
    else if (std.mem.eql(u8, span_name, "vkEnumerateDeviceLayerProperties"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EnumerateDeviceLayerProperties));
    }
    else if (std.mem.eql(u8, span_name, "vkEnumerateDeviceExtensionProperties"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EnumerateDeviceExtensionProperties));
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
    return @ptrCast(@alignCast(vk_global_state.init_wrapper.?.pfn_next_get_device_proc_addr(device, p_name)));
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
    else if (std.mem.eql(u8, span_name, "vkEnumerateInstanceLayerProperties"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EnumerateInstanceLayerProperties));
    }
    else if (std.mem.eql(u8, span_name, "vkEnumerateInstanceExtensionProperties"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EnumerateInstanceExtensionProperties));
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
    else if (std.mem.eql(u8, span_name, "vkEnumerateDeviceLayerProperties"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EnumerateDeviceLayerProperties));
    }
    else if (std.mem.eql(u8, span_name, "vkEnumerateDeviceExtensionProperties"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EnumerateDeviceExtensionProperties));
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
    return @ptrCast(@alignCast(vk_global_state.base_wrapper.?.getInstanceProcAddr(instance, p_name)));
}
