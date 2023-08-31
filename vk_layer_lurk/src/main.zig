const builtin = @import("builtin");
const std = @import("std");

const disc = @import("discord_conn_holder.zig");
const setup = @import("setup.zig");
const vk_global_state = @import("vk_global_state.zig");
const vk_layer_stubs = @import("vk_layer_stubs.zig");
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

// single global lock, for simplicity
var global_lock: std.Thread.Mutex = .{};

// layer book-keeping information, to store dispatch tables
// A hash table isn't needed as this layer is only given one device and one
// instance
var device_dispatcher: ?vk_layer_stubs.LayerDispatchTable = null;
var layer_dispatcher: ?vk_layer_stubs.LayerInitDispatchTable = null;


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
    global_lock.lock();
    defer global_lock.unlock();

    vk_setup_wrappers.create_instance_wrapper(p_create_info, p_instance);
    if (vk_global_state.base_wrapper == null or vk_global_state.instance_wrapper == null)
    {
        return vk.Result.error_initialization_failed;
    }

    return vk_global_state.base_wrapper.?.dispatch.vkCreateInstance(p_create_info, p_allocator, p_instance);
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

    {
        global_lock.lock();
        defer global_lock.unlock();
        setup.destroy_instance(instance, vk_global_state.instance_wrapper.?);
        vk_global_state.instance_wrapper = null;
    }
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
    const local_layer_dispatcher = vk_layer_stubs.LayerInitDispatchTable.init(p_create_info);
    const gdpa = local_layer_dispatcher.pfn_next_get_device_proc_addr;
    const gipa = local_layer_dispatcher.pfn_next_get_instance_proc_addr;

    const createFunc: vk.PfnCreateDevice = @ptrCast(gipa(vk.Instance.null_handle, "vkCreateDevice"));
    const create_device_result = createFunc(physical_device, p_create_info, p_allocator, p_device);
    if (create_device_result != vk.Result.success) @panic("Vulkan function call failed: vkCreateDevice");

    // fetch our own dispatch table for the functions we need, into the next
    // layer
    const device = p_device.*;
    var dispatch_table: vk_layer_stubs.LayerDispatchTable = undefined;
    dispatch_table.AllocateCommandBuffers = @ptrCast(gdpa(device, "vkAllocateCommandBuffers"));
    dispatch_table.AllocateDescriptorSets = @ptrCast(gdpa(device, "vkAllocateDescriptorSets"));
    dispatch_table.AllocateMemory = @ptrCast(gdpa(device, "vkAllocateMemory"));
    dispatch_table.BeginCommandBuffer = @ptrCast(gdpa(device, "vkBeginCommandBuffer"));
    dispatch_table.BindBufferMemory = @ptrCast(gdpa(device, "vkBindBufferMemory"));
    dispatch_table.BindImageMemory = @ptrCast(gdpa(device, "vkBindImageMemory"));
    dispatch_table.CmdBeginRenderPass = @ptrCast(gdpa(device, "vkCmdBeginRenderPass"));
    dispatch_table.CmdBindDescriptorSets = @ptrCast(gdpa(device, "vkCmdBindDescriptorSets"));
    dispatch_table.CmdBindIndexBuffer = @ptrCast(gdpa(device, "vkCmdBindIndexBuffer"));
    dispatch_table.CmdBindPipeline = @ptrCast(gdpa(device, "vkCmdBindPipeline"));
    dispatch_table.CmdBindVertexBuffers = @ptrCast(gdpa(device, "vkCmdBindVertexBuffers"));
    dispatch_table.CmdCopyBufferToImage = @ptrCast(gdpa(device, "vkCmdCopyBufferToImage"));
    dispatch_table.CmdDraw = @ptrCast(gdpa(device, "vkCmdDraw"));
    dispatch_table.CmdDrawIndexed = @ptrCast(gdpa(device, "vkCmdDrawIndexed"));
    dispatch_table.CmdEndRenderPass = @ptrCast(gdpa(device, "vkCmdEndRenderPass"));
    dispatch_table.CmdPipelineBarrier = @ptrCast(gdpa(device, "vkCmdPipelineBarrier"));
    dispatch_table.CmdPushConstants = @ptrCast(gdpa(device, "vkCmdPushConstants"));
    dispatch_table.CmdSetScissor = @ptrCast(gdpa(device, "vkCmdSetScissor"));
    dispatch_table.CmdSetViewport = @ptrCast(gdpa(device, "vkCmdSetViewport"));
    dispatch_table.CreateBuffer = @ptrCast(gdpa(device, "vkCreateBuffer"));
    dispatch_table.CreateCommandPool = @ptrCast(gdpa(device, "vkCreateCommandPool"));
    dispatch_table.CreateDescriptorPool = @ptrCast(gdpa(device, "vkCreateDescriptorPool"));
    dispatch_table.CreateDescriptorSetLayout = @ptrCast(gdpa(device, "vkCreateDescriptorSetLayout"));
    dispatch_table.CreateFence = @ptrCast(gdpa(device, "vkCreateFence"));
    dispatch_table.CreateFramebuffer = @ptrCast(gdpa(device, "vkCreateFramebuffer"));
    dispatch_table.CreateGraphicsPipelines = @ptrCast(gdpa(device, "vkCreateGraphicsPipelines"));
    dispatch_table.CreateImage = @ptrCast(gdpa(device, "vkCreateImage"));
    dispatch_table.CreateImageView = @ptrCast(gdpa(device, "vkCreateImageView"));
    dispatch_table.CreatePipelineLayout = @ptrCast(gdpa(device, "vkCreatePipelineLayout"));
    dispatch_table.CreateRenderPass = @ptrCast(gdpa(device, "vkCreateRenderPass"));
    dispatch_table.CreateSampler = @ptrCast(gdpa(device, "vkCreateSampler"));
    dispatch_table.CreateSemaphore = @ptrCast(gdpa(device, "vkCreateSemaphore"));
    dispatch_table.CreateShaderModule = @ptrCast(gdpa(device, "vkCreateShaderModule"));
    dispatch_table.CreateSwapchainKHR = @ptrCast(gdpa(device, "vkCreateSwapchainKHR"));
    dispatch_table.DestroyBuffer = @ptrCast(gdpa(device, "vkDestroyBuffer"));
    dispatch_table.DestroyDevice = @ptrCast(gdpa(device, "vkDestroyDevice"));
    dispatch_table.DestroyRenderPass = @ptrCast(gdpa(device, "vkDestroyRenderPass"));
    dispatch_table.DestroyShaderModule = @ptrCast(gdpa(device, "vkDestroyShaderModule"));
    dispatch_table.DestroySwapchainKHR = @ptrCast(gdpa(device, "vkDestroySwapchainKHR"));
    dispatch_table.EndCommandBuffer = @ptrCast(gdpa(device, "vkEndCommandBuffer"));
    dispatch_table.FlushMappedMemoryRanges = @ptrCast(gdpa(device, "vkFlushMappedMemoryRanges"));
    dispatch_table.FreeMemory = @ptrCast(gdpa(device, "vkFreeMemory"));
    dispatch_table.GetBufferMemoryRequirements = @ptrCast(gdpa(device, "vkGetBufferMemoryRequirements"));
    dispatch_table.GetDeviceProcAddr = @ptrCast(gdpa(device, "vkGetDeviceProcAddr"));
    dispatch_table.GetDeviceQueue = @ptrCast(gdpa(device, "vkGetDeviceQueue"));
    dispatch_table.GetFenceStatus = @ptrCast(gdpa(device, "vkGetFenceStatus"));
    dispatch_table.GetImageMemoryRequirements = @ptrCast(gdpa(device, "vkGetImageMemoryRequirements"));
    dispatch_table.GetSwapchainImagesKHR = @ptrCast(gdpa(device, "vkGetSwapchainImagesKHR"));
    dispatch_table.MapMemory = @ptrCast(gdpa(device, "vkMapMemory"));
    dispatch_table.QueuePresentKHR = @ptrCast(gdpa(device, "vkQueuePresentKHR"));
    dispatch_table.QueueSubmit = @ptrCast(gdpa(device, "vkQueueSubmit"));
    dispatch_table.ResetCommandBuffer = @ptrCast(gdpa(device, "vkResetCommandBuffer"));
    dispatch_table.ResetFences = @ptrCast(gdpa(device, "vkResetFences"));
    dispatch_table.UnmapMemory = @ptrCast(gdpa(device, "vkUnmapMemory"));
    dispatch_table.UpdateDescriptorSets = @ptrCast(gdpa(device, "vkUpdateDescriptorSets"));
    dispatch_table.WaitForFences = @ptrCast(gdpa(device, "vkWaitForFences"));

    // store layer global device dispatch table
    {
        global_lock.lock();
        defer global_lock.unlock();
        device_dispatcher = dispatch_table;
        layer_dispatcher = local_layer_dispatcher;
    }

    setup.get_physical_mem_props(physical_device, vk_global_state.instance_wrapper.?);
    setup.device_map_queues
    (
        physical_device,
        device,
        device_dispatcher.?,
        vk_global_state.instance_wrapper.?,
        layer_dispatcher.?,
        p_create_info,
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
    {
        global_lock.lock();
        defer global_lock.unlock();
        device_dispatcher = null;
    }
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
    const result = device_dispatcher.?.CreateSwapchainKHR(device, p_create_info, p_allocator, p_swapchain);
    if (result != vk.Result.success) return result;

    {
        global_lock.lock();
        defer global_lock.unlock();
        setup.setup_swapchain(device, device_dispatcher.?, p_create_info, p_swapchain);
    }

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
    global_lock.lock();
    defer global_lock.unlock();

    device_dispatcher.?.DestroySwapchainKHR(device, swapchain, p_allocator);
    setup.destroy_swapchain(device, device_dispatcher.?);
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
        global_lock.lock();
        defer global_lock.unlock();
        const queue_data = setup.wait_before_queue_present(queue, device_dispatcher.?);

        {
            var i: u32 = 0;
            while (i < p_present_info.swapchain_count) : (i += 1)
            {
                const maybe_draw_data = setup.before_present
                (
                    device_dispatcher.?,
                    layer_dispatcher.?,
                    queue_data,
                    p_present_info.p_wait_semaphores,
                    p_present_info.wait_semaphore_count,
                    p_present_info.p_image_indices[i]
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

                const chain_result = device_dispatcher.?.QueuePresentKHR(queue, &present_info);

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

        global_lock.lock();
        defer global_lock.unlock();
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

    global_lock.lock();
    defer global_lock.unlock();
    const table =
        device_dispatcher
        orelse @panic("GetDeviceProcAddr failed to get dispatch table");
    return @ptrCast(@alignCast(table.GetDeviceProcAddr(device, p_name)));
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

    global_lock.lock();
    defer global_lock.unlock();
    return @ptrCast(@alignCast(vk_global_state.base_wrapper.?.getInstanceProcAddr(instance, p_name)));
}
