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

    vk_setup_wrappers.create_instance_wrappers(p_create_info, p_allocator, p_instance);
    if (vk_global_state.base_wrapper != null and vk_global_state.instance_wrapper != null)
    {
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
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Create Device: " ++ LAYER_NAME, .{});

    vk_setup_wrappers.create_device_wrappers(physical_device, p_create_info, p_allocator, p_device);
    var device_data: *vkt.DeviceData = vk_global_state.device_backing.peek_head().?;

    setup.get_physical_mem_props(physical_device, vk_global_state.instance_wrapper.?);
    setup.device_map_queues
    (
        p_create_info,
        physical_device,
        device_data.device,
        device_data.set_device_loader_data_func,
        device_data.device_wrapper,
        vk_global_state.instance_wrapper.?,
        &device_data.device_queues,
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
    _ = device;
    _ = p_allocator;
    vk_global_state.wrappers_global_lock.lock();
    defer vk_global_state.wrappers_global_lock.unlock();
    if (builtin.mode == .Debug) std.log.scoped(.VKLURK).debug("Destroy Device: " ++ LAYER_NAME, .{});

    _ = vk_global_state.device_backing.pop();
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
    var device_data: *vkt.DeviceData = vk_global_state.device_backing.peek_tail().?;

    const result = device_data.device_wrapper.dispatch.vkCreateSwapchainKHR
    (
        device,
        p_create_info,
        p_allocator,
        p_swapchain,
    );
    if (result != vk.Result.success) return result;

    device_data.swapchain_backing.push
    (
        vkt.SwapchainData
        {
            .command_pool = null,
            .descriptor_layout = null,
            .descriptor_pool = null,
            .descriptor_set = null,
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
        },
    )
    catch @panic("oom");
    var swapchain_data = device_data.swapchain_backing.peek_head();

    setup.setup_swapchain
    (
        device,
        device_data.device_wrapper,
        p_create_info,
        swapchain_data.?,
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

    var maybe_device_data: ?*vkt.DeviceData = vk_global_state.device_backing.peek_tail();
    if (maybe_device_data != null)
    {
        var device_data = maybe_device_data.?;
        if (swapchain == .null_handle)
        {
            device_data.device_wrapper.destroySwapchainKHR(device, swapchain, p_allocator);
            return;
        }

        var maybe_swapchain_data: ?vkt.SwapchainData = device_data.swapchain_backing.pop();
        if (maybe_swapchain_data != null)
        {
            var swapchain_data = maybe_swapchain_data.?;
            setup.destroy_swapchain
            (
                device,
                device_data.device_wrapper,
                @constCast(&swapchain_data),
                &device_data.previous_draw_data,
            );
            device_data.device_wrapper.destroySwapchainKHR(device, swapchain, p_allocator);

            return;
        }

        @panic("Failed to destroy swapchain, specified swapchain not found in backing buffer.");
    }

    @panic("Failed to destroy swapchain, specified device not found in backing buffer");
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
        var device_data: *vkt.DeviceData = vk_global_state.device_backing.peek_tail().?;

        const queue_data = setup.wait_before_queue_present
        (
            device_data.device,
            device_data.device_wrapper,
            queue,
            &device_data.device_queues,
        );

        {
            disc.output_lock.lock();
            defer disc.output_lock.unlock();

            var i: u32 = 0;
            while (i < p_present_info.swapchain_count) : (i += 1)
            {
                var swapchain = p_present_info.p_swapchains[i];
                var maybe_swapchain_data: ?*vkt.SwapchainData = device_data.swapchain_backing.peek_tail();
                if (maybe_swapchain_data != null)
                {
                    var swapchain_data = maybe_swapchain_data.?;
                    if (swapchain != swapchain_data.swapchain.?) return vk.Result.error_unknown;

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
                        swapchain_data,
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
    return @ptrCast(@alignCast(vk_global_state.instance_wrapper.?.getDeviceProcAddr(device, p_name)));
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
