const builtin = @import("builtin");
const std = @import("std");

const disc = @import("discord_conn_holder.zig");
const setup = @import("setup.zig");
const vk_layer_stubs = @import("vk_layer_stubs.zig");

const vk = @import("vk.zig");


///////////////////////////////////////////////////////////////////////////////
// Layer globals definition

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

// differentiate this layer from the c++ implementation
const LAYER_NAME = "VK_LAYER_Lurk";
const LAYER_DESC =
    "Lurk as a Vulkan Layer - " ++
    "https://github.com/joshua-software-dev/Lurk";

// c_allocator easy access
const c_allocator = std.heap.c_allocator;

// single global lock, for simplicity
var global_lock: std.Thread.Mutex = .{};

// layer book-keeping information, to store dispatch tables
// A hash table isn't needed as this layer is only given one device and one
// instance
var device_dispatcher: ?vk_layer_stubs.LayerDispatchTable = null;
var instance_dispatcher: ?vk_layer_stubs.LayerInstanceDispatchTable = null;

// actual data we're recording in this layer
const CommandStats = extern struct
{
    draw_count: u32,
    instance_count: u32,
    vert_count: u32
};
// there are actually multiple of these, so a hash table is an acceptable
// choice, however we store the actual object reference as the key rather than
// manipulating pointers for use as keys
var command_buffer_stats =
    std.AutoHashMap(vk.CommandBuffer, CommandStats).init(c_allocator);


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
    // Ensure this is a nullable pointer (?*) to allow stepping through the
    // chain of p_next
    var layer_create_info: ?*vk_layer_stubs.LayerInstanceCreateInfo =
        @ptrCast(@alignCast(@constCast(p_create_info.p_next)));

    // step through the chain of p_next until we get to the link info
    while
    (
        layer_create_info != null and
        (
            layer_create_info.?.s_type != vk.StructureType.loader_instance_create_info or
            layer_create_info.?.function != vk_layer_stubs.LayerFunction_LAYER_LINK_INFO
        )
    )
    {
        layer_create_info = @ptrCast(@alignCast(@constCast(layer_create_info.?.p_next)));
    }

    if(layer_create_info == null)
    {
        // No loader instance create info
        return vk.Result.error_initialization_failed;
    }

    // create non-null pointer variable to make further interactions with this
    // type easier
    var final_lci: *vk_layer_stubs.LayerDeviceCreateInfo =
        @ptrCast(layer_create_info orelse unreachable);

    var gpa = final_lci.u.p_layer_info.pfn_next_get_instance_proc_addr;
    // move chain on for next layer
    final_lci.u.p_layer_info = final_lci.u.p_layer_info.p_next;

    const createFunc: vk.PfnCreateInstance =
        @ptrCast(gpa(vk.Instance.null_handle, "vkCreateInstance"));
    // the original cpp version never uses this value despite saving it, I've
    // opted to discard it instead
    _ = createFunc(p_create_info, p_allocator, p_instance);

    // fetch our own dispatch table for the functions we need, into the next
    // layer
    const instance = p_instance.*;
    var dispatch_table: vk_layer_stubs.LayerInstanceDispatchTable = undefined;
    dispatch_table.GetInstanceProcAddr = @ptrCast(gpa(instance, "vkGetInstanceProcAddr"));
    dispatch_table.DestroyInstance = @ptrCast(gpa(instance, "vkDestroyInstance"));
    dispatch_table.EnumerateDeviceExtensionProperties =
        @ptrCast(gpa(instance, "vkEnumerateDeviceExtensionProperties"));

    // store layer global instance dispatch table
    {
        global_lock.lock();
        defer global_lock.unlock();
        instance_dispatcher = dispatch_table;
    }

    return vk.Result.success;
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
        setup.destroy_instance(instance, instance_dispatcher.?);
        instance_dispatcher = null;
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
    // Ensure this is a nullable pointer (?*) to allow stepping through the
    // chain of p_next
    var layer_create_info: ?*vk_layer_stubs.LayerDeviceCreateInfo =
        @ptrCast(@alignCast(@constCast(p_create_info.p_next)));

    // step through the chain of p_next until we get to the link info
    while
    (
        layer_create_info != null and
        (
            layer_create_info.?.s_type != vk.StructureType.loader_device_create_info or
            layer_create_info.?.function != vk_layer_stubs.LayerFunction_LAYER_LINK_INFO
        )
    )
    {
        layer_create_info = @ptrCast(@alignCast(@constCast(layer_create_info.?.p_next)));
    }

    if(layer_create_info == null)
    {
        // No loader instance create info
        return vk.Result.error_initialization_failed;
    }

    // create non-null pointer variable to make further interactions with this
    // type easier
    var final_lci: *vk_layer_stubs.LayerDeviceCreateInfo =
        @ptrCast(layer_create_info orelse unreachable);

    var gipa = final_lci.u.p_layer_info.pfn_next_get_instance_proc_addr;
    var gdpa = final_lci.u.p_layer_info.pfn_next_get_device_proc_addr;
    // move chain on for next layer
    final_lci.u.p_layer_info = final_lci.u.p_layer_info.p_next;

    const createFunc: vk.PfnCreateDevice =
        @ptrCast(gipa(vk.Instance.null_handle, "vkCreateDevice"));
    // the original cpp version never uses this value despite saving it, I've
    // opted to discard it instead
    _ = createFunc(physical_device, p_create_info, p_allocator, p_device);

    // fetch our own dispatch table for the functions we need, into the next
    // layer
    const device = p_device.*;
    var dispatch_table: vk_layer_stubs.LayerDispatchTable = undefined;
    dispatch_table.GetDeviceProcAddr = @ptrCast(gdpa(device, "vkGetDeviceProcAddr"));
    dispatch_table.DestroyDevice = @ptrCast(gdpa(device, "vkDestroyDevice"));
    dispatch_table.BeginCommandBuffer = @ptrCast(gdpa(device, "vkBeginCommandBuffer"));
    dispatch_table.CmdDraw = @ptrCast(gdpa(device, "vkCmdDraw"));
    dispatch_table.CmdDrawIndexed = @ptrCast(gdpa(device, "vkCmdDrawIndexed"));
    dispatch_table.EndCommandBuffer = @ptrCast(gdpa(device, "vkEndCommandBuffer"));
    dispatch_table.CreateSwapchainKHR = @ptrCast(gdpa(device, "vkCreateSwapchainKHR"));
    dispatch_table.DestroySwapchainKHR = @ptrCast(gdpa(device, "vkDestroySwapchainKHR"));
    dispatch_table.QueuePresentKHR = @ptrCast(gdpa(device, "vkQueuePresentKHR"));
    dispatch_table.CreateRenderPass = @ptrCast(gdpa(device, "vkCreateRenderPass"));
    dispatch_table.DestroyRenderPass = @ptrCast(gdpa(device, "vkDestroyRenderPass"));

    // store layer global device dispatch table
    {
        global_lock.lock();
        defer global_lock.unlock();
        device_dispatcher = dispatch_table;
    }

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

export fn VkLayerLurk_BeginCommandBuffer
(
    command_buffer: vk.CommandBuffer,
    p_begin_info: *const vk.CommandBufferBeginInfo
)
callconv(vk.vulkan_call_conv) vk.Result
{
    global_lock.lock();
    defer global_lock.unlock();

    var stats = CommandStats
    {
        .draw_count = 0,
        .instance_count = 0,
        .vert_count = 0
    };
    command_buffer_stats
        .put(command_buffer, stats)
        catch @panic("BeginCommandBuffer stats table OOM");

    const table =
        device_dispatcher
        orelse @panic("BeginCommandBuffer failed to get dispatch table");
    return table.BeginCommandBuffer(command_buffer, p_begin_info);
}

export fn VkLayerLurk_CmdDraw
(
    command_buffer: vk.CommandBuffer,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32
)
callconv(vk.vulkan_call_conv) void
{
    global_lock.lock();
    defer global_lock.unlock();

    var stats =
        command_buffer_stats.get(command_buffer)
        orelse @panic("CmdDraw failed to get command buffer stats");
    stats.draw_count += 1;
    stats.instance_count += instance_count;
    stats.vert_count += instance_count * vertex_count;

    command_buffer_stats
        .put(command_buffer, stats)
        catch @panic("SampleLayerZig_CmdDraw stats table OOM");

    const table =
        device_dispatcher
        orelse @panic("CmdDraw failed to get dispatch table");
    table.CmdDraw
    (
        command_buffer,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance
    );
}

export fn VkLayerLurk_CmdDrawIndexed
(
    command_buffer: vk.CommandBuffer,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32
)
callconv(vk.vulkan_call_conv) void
{
    global_lock.lock();
    defer global_lock.unlock();

    var stats =
        command_buffer_stats.get(command_buffer)
        orelse @panic("CmdDrawIndexed failed to get command buffer stats");
    stats.draw_count += 1;
    stats.instance_count += instance_count;
    stats.vert_count += instance_count * index_count;

    command_buffer_stats
        .put(command_buffer, stats)
        catch @panic("SampleLayerZig_CmdDrawIndexed stats table OOM");

    const table =
        device_dispatcher
        orelse @panic("CmdDrawIndexed failed to get dispatch table");
    table.CmdDrawIndexed
    (
        command_buffer,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance
    );
}

export fn VkLayerLurk_EndCommandBuffer
(
    command_buffer: vk.CommandBuffer
)
callconv(vk.vulkan_call_conv) vk.Result
{
    global_lock.lock();
    defer global_lock.unlock();

    if (command_buffer_stats.get(command_buffer)) |stats|
    {
        std.log.scoped(.LAYER).debug
        (
            "Command buffer 0x{x} ended with " ++
            "{} draws, " ++
            "{} instances, and " ++
            "{} vertices",
            .{
                @intFromPtr(&command_buffer),
                stats.draw_count,
                stats.instance_count,
                stats.vert_count
            }
        );

        // Ensure this table actually removes the command buffer and doesn't
        // endlessly accumulate entries
        _ = command_buffer_stats.remove(command_buffer);
    }
    else
    {
        std.log.scoped(.LAYER).warn
        (
            "WARNING: EndCommandBuffer failed to get command buffer stats\n",
            .{}
        );
    }

    const table =
        device_dispatcher
        orelse @panic("EndCommandBuffer failed to get dispatch table");
    return table.EndCommandBuffer(command_buffer);
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
        const table =
            instance_dispatcher
            orelse @panic
            (
                "EnumerateDeviceExtensionProperties " ++
                "failed to get dispatch table"
            );
        return table.EnumerateDeviceExtensionProperties
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

    setup.setup_swapchain(device, device_dispatcher.?, p_create_info);
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
    device_dispatcher.?.DestroySwapchainKHR(device, swapchain, p_allocator);
    {
        global_lock.lock();
        defer global_lock.unlock();
        setup.destroy_swapchain(device, device_dispatcher.?);
    }
}

export fn VkLayerLurk_QueuePresentKHR
(
    queue: vk.Queue,
    p_present_info: *const vk.PresentInfoKHR,
)
callconv(vk.vulkan_call_conv) vk.Result
{
    return device_dispatcher.?.QueuePresentKHR(queue, p_present_info);
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
    else if (std.mem.eql(u8, span_name, "vkBeginCommandBuffer"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_BeginCommandBuffer));
    }
    else if (std.mem.eql(u8, span_name, "vkCmdDraw"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CmdDraw));
    }
    else if (std.mem.eql(u8, span_name, "vkCmdDrawIndexed"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CmdDrawIndexed));
    }
    else if (std.mem.eql(u8, span_name, "vkEndCommandBuffer"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EndCommandBuffer));
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
    disc.start_discord_conn(c_allocator) catch @panic("Failed to start discord connection.");

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
    else if (std.mem.eql(u8, span_name, "vkBeginCommandBuffer"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_BeginCommandBuffer));
    }
    else if (std.mem.eql(u8, span_name, "vkCmdDraw"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CmdDraw));
    }
    else if (std.mem.eql(u8, span_name, "vkCmdDrawIndexed"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_CmdDrawIndexed));
    }
    else if (std.mem.eql(u8, span_name, "vkEndCommandBuffer"))
    {
        return @ptrCast(@alignCast(&VkLayerLurk_EndCommandBuffer));
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
        instance_dispatcher
        orelse @panic("GetInstanceProcAddr failed to get dispatch table");
    return @ptrCast(@alignCast(table.GetInstanceProcAddr(instance, p_name)));
}
