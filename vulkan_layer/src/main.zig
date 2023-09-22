const builtin = @import("builtin");
const std = @import("std");

const build_options = @import("vulkan_layer_build_options");
const setup = @import("setup/vk_setup.zig");
const vk_global_state = @import("setup/vk_global_state.zig");
const vk_setup_wrappers = @import("setup/vk_setup_wrappers.zig");
const vkt = @import("setup/vk_types.zig");

const overlay_gui = @import("overlay_gui");
const vk = @import("vk");


// Zig scoped logger set based on compile mode
pub const std_options = struct
{
    pub const log_scope_levels: []const std.log.ScopeLevel =
    &[_]std.log.ScopeLevel
    {
        .{
            .scope = .OVERLAY,
            .level = switch (builtin.mode)
            {
                .Debug => .debug,
                else => .info,
            }
        },
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
    .arm, .armeb => "arm32",
    .aarch64, .aarch64_be, .aarch64_32 => "arm64",
    else => if (!build_options.allow_any_arch) @panic("Unsupported CPU architecture"),
};
const LAYER_DESC =
    "Lurk as a Vulkan Layer - " ++
    "https://github.com/joshua-software-dev/Lurk";

const MAX_MEMORY_ALLOCATION = 1024 * 512; // bytes

// Create compile time hashmaps that specify which functions this layer intends
// to hook into
const DeviceRegistionFunctionMap = std.ComptimeStringMap
(
    vk.PfnVoidFunction,
    .{
        .{
            vk.InstanceCommandFlags.cmdName(.getDeviceProcAddr),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_GetDeviceProcAddr)))
        },
        .{
            vk.InstanceCommandFlags.cmdName(.createDevice),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_CreateDevice)))
        },
        .{
            vk.DeviceCommandFlags.cmdName(.destroyDevice),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_DestroyDevice)))
        },
        .{
            vk.DeviceCommandFlags.cmdName(.createSwapchainKHR),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_CreateSwapchainKHR)))
        },
        .{
            vk.DeviceCommandFlags.cmdName(.destroySwapchainKHR),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_DestroySwapchainKHR)))
        },
        .{
            vk.DeviceCommandFlags.cmdName(.queuePresentKHR),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_QueuePresentKHR)))
        },
    },
);

const InstanceRegistionFunctionMap = std.ComptimeStringMap
(
    vk.PfnVoidFunction,
    .{
        .{
            vk.BaseCommandFlags.cmdName(.getInstanceProcAddr),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_GetInstanceProcAddr)))
        },
        .{
            vk.BaseCommandFlags.cmdName(.createInstance),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_CreateInstance)))
        },
        .{
            vk.InstanceCommandFlags.cmdName(.destroyInstance),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_DestroyInstance)))
        },
    },
);

const BlacklistRegistionFunctionMap = std.ComptimeStringMap
(
    vk.PfnVoidFunction,
    .{
        .{
            vk.BaseCommandFlags.cmdName(.createInstance),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_CreateInstance)))
        },
        .{
            vk.InstanceCommandFlags.cmdName(.destroyInstance),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_DestroyInstance)))
        },
        .{
            vk.InstanceCommandFlags.cmdName(.createDevice),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_CreateDevice)))
        },
        .{
            vk.DeviceCommandFlags.cmdName(.destroyDevice),
            @as(vk.PfnVoidFunction, @ptrCast(@alignCast(&VkLayerLurk_DestroyDevice)))
        },
    },
);

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
    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();

        std.log.scoped(.VKLURK).debug("Create Instance: {d}" ++ LAYER_NAME, .{ p_instance.* });

        if (vk_setup_wrappers.create_instance_wrappers(p_create_info, p_allocator, p_instance)) |inst_data|
        {
            if (!vk_global_state.first_alloc_complete)
            {
                vk_global_state.first_alloc_complete = true;
                vk_global_state.heap_buf = std.heap.c_allocator.create([MAX_MEMORY_ALLOCATION]u8) catch @panic("oom");
                vk_global_state.heap_fba = std.heap.FixedBufferAllocator.init(vk_global_state.heap_buf);

                vk_global_state.device_backing =
                    vkt.DeviceDataHashMap.init(vk_global_state.heap_fba.allocator());
                vk_global_state.device_backing.ensureTotalCapacity(8) catch @panic("oom");

                vk_global_state.instance_backing =
                    vkt.InstanceDataHashMap.init(vk_global_state.heap_fba.allocator());
                vk_global_state.instance_backing.ensureTotalCapacity(8) catch @panic("oom");

                vk_global_state.swapchain_backing =
                    vkt.SwapchainDataHashMap.init(vk_global_state.heap_fba.allocator());
                vk_global_state.swapchain_backing.ensureTotalCapacity(8) catch @panic("oom");

                std.log.scoped(.VKLURK).debug("Post backing alloc: {d}", .{ vk_global_state.heap_fba.end_index });
            }

            var backing = vk_global_state.instance_backing.getOrPut(p_instance.*) catch @panic("oom");
            if (backing.found_existing)
            {
                @panic("Found an existing Instance with the same id when creating a new one");
            }
            backing.value_ptr.* = inst_data;

            setup.map_physical_devices_to_instance(backing.value_ptr);
            return vk.Result.success;
        }
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
    std.log.scoped(.VKLURK).debug("Destroy Instance: " ++ LAYER_NAME, .{});

    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();

        var instance_data = vk_global_state.instance_backing.fetchRemove(instance).?;
        std.log.scoped(.VKLURK).debug
        (
            "Destroyed Instance ID: {d}|{d}",
            .{
                instance_data.value.instance_id,
                instance_data.value.instance
            }
        );
        setup.destroy_instance(instance, instance_data.value.instance_wrapper);

        if (vk_global_state.instance_backing.count() == 0)
        {
            overlay_gui.disch.stop_discord_conn();
            std.heap.c_allocator.free(vk_global_state.heap_buf);
            vk_global_state.heap_buf = undefined;
            vk_global_state.heap_fba = undefined;
            vk_global_state.first_alloc_complete = false;
        }

        return;
    }

    @panic("Failed to get global vtable lock");
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
    const proc_is_blacklisted =
        overlay_gui.blacklist.is_this_process_blacklisted()
        catch @panic("Failed to validate process blacklist");

    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();

        if (!proc_is_blacklisted and vk_global_state.device_backing.count() < 1)
        {
            // Internal logic makes connecting multiple times idempotent
            overlay_gui.disch.start_discord_conn(vk_global_state.heap_fba.allocator())
            catch @panic("Failed to start discord connection.");

            std.log.scoped(.VKLURK).debug("Post connection alloc: {d}", .{ vk_global_state.heap_fba.end_index });
        }

        std.log.scoped(.VKLURK).debug("Create Device: {d}" ++ LAYER_NAME, .{ p_device.* });

        var device_data = vk_setup_wrappers.create_device_wrappers
        (
            physical_device,
            p_create_info,
            p_allocator,
            p_device
        );

        const maybe_instance_data: ?vkt.InstanceData =
        blk: {
            var it = vk_global_state.instance_backing.iterator();
            while (it.next()) |kv|
            {
                for (kv.value_ptr.physical_devices.constSlice()) |dev|
                {
                    if (dev == physical_device) break :blk kv.value_ptr.*;
                }
            }

            break :blk null;
        };

        const instance_data = maybe_instance_data.?;

        setup.device_map_queues
        (
            p_create_info,
            physical_device,
            device_data.device,
            device_data.set_device_loader_data_func,
            instance_data.instance_wrapper,
            device_data.device_wrapper,
            &device_data.queues,
            &device_data.graphic_queue,
        );

        return vk.Result.success;
    }

    return vk.Result.error_initialization_failed;
}

export fn VkLayerLurk_DestroyDevice
(
    device: vk.Device,
    p_allocator: ?*const vk.AllocationCallbacks
)
callconv(vk.vulkan_call_conv) void
{
    _ = p_allocator;
    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();

        std.log.scoped(.VKLURK).debug("Destroy Device: " ++ LAYER_NAME, .{});

        if (vk_global_state.device_backing.fetchRemove(device)) |dev|
        {
            std.log.scoped(.VKLURK).debug("Destroyed Device ID: {d}|{d}", .{ dev.value.device_id, dev.value.device });
        }
        return;
    }

    @panic("Failed to get global vtable lock");
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
    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();

        std.log.scoped(.VKLURK).debug("Create Swapchain: {d}" ++ LAYER_NAME, .{ p_swapchain.* });
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
            std.log.scoped(.VKLURK).warn
            (
                "A new instance was requested with the same memory address as an existing one.",
                .{}
            );
            setup.destroy_swapchain
            (
                device,
                device_data.device_wrapper,
                backing.value_ptr,
                &device_data.previous_draw_data,
            );
        }

        std.log.scoped(.VKLURK).debug("Current Swapchain Ref: {d}", .{ vk_global_state.swapchain_ref_count });
        vk_global_state.swapchain_ref_count += 1;
        std.log.scoped(.VKLURK).debug
        (
            "New Swapchain Ref: {d}|{d}",
            .{
                vk_global_state.swapchain_ref_count,
                swapchain,
            },
        );
        backing.value_ptr.* = vkt.SwapchainData
        {
            .swapchain_id = vk_global_state.swapchain_ref_count,
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
            .swapchain = swapchain,
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
            device_data.graphic_queue.?,
        );

        return result;
    }

    return vk.Result.error_unknown;
}

export fn VkLayerLurk_DestroySwapchainKHR
(
    device: vk.Device,
    swapchain: vk.SwapchainKHR,
    p_allocator: ?*const vk.AllocationCallbacks,
)
callconv(vk.vulkan_call_conv) void
{
    const lock_success = vk_global_state.wrappers_global_lock.tryLock();
    if (!lock_success)
    {
        std.log.scoped(.VKLURK).err("Failed to get global vtable lock", .{});
    }
    defer if (lock_success) vk_global_state.wrappers_global_lock.unlock();

    std.log.scoped(.VKLURK).debug("Destroy Swapchain: " ++ LAYER_NAME, .{});

    if (swapchain == .null_handle)
    {
        var device_data: vkt.DeviceData = vk_global_state.device_backing.get(device).?;
        device_data.device_wrapper.destroySwapchainKHR(device, swapchain, p_allocator);
        return;
    }

    var swapchain_data = vk_global_state.swapchain_backing.fetchRemove(swapchain).?;
    std.log.scoped(.VKLURK).debug
    (
        "Destroyed Swapchain ID: {d}|{d}",
        .{
            swapchain_data.value.swapchain_id,
            swapchain_data.value.swapchain.?
        },
    );
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

    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();

        var maybe_device_data: ?*vkt.DeviceData = null;
        var maybe_queue_data: ?*vkt.VkQueueData =
        blk: {
            var it = vk_global_state.device_backing.iterator();
            while (it.next()) |kv|
            {
                for (kv.value_ptr.queues.slice()) |queue_data|
                {
                    if (queue_data.queue == queue)
                    {
                        maybe_device_data = @constCast(kv.value_ptr);
                        break :blk @constCast(&queue_data);
                    }
                }
            }

            break :blk null;
        };

        var device_data = maybe_device_data.?;
        var queue_data = maybe_queue_data.?;

        setup.wait_before_queue_present
        (
            device_data.device,
            device_data.device_wrapper,
            queue,
            queue_data,
        );

        {
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
                    device_data.graphic_queue.?,
                    &device_data.previous_draw_data,
                    swapchain_data.?
                ) catch |err|
                {
                    std.log.scoped(.VKLURK).err("{any}", .{ err });
                    return final_result;
                };

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
    const proc_is_blacklisted =
        overlay_gui.blacklist.is_this_process_blacklisted()
        catch @panic("Failed to validate process blacklist");

    if (proc_is_blacklisted)
    {
        const bl_func = BlacklistRegistionFunctionMap.get(span_name);
        if (bl_func != null) return bl_func.?;
    }
    else
    {
        const device_func = DeviceRegistionFunctionMap.get(span_name);
        if (device_func != null) return device_func.?;
    }

    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();
        const device_data: vkt.DeviceData = vk_global_state.device_backing.get(device).?;
        return @ptrCast(@alignCast(device_data.get_device_proc_addr_func(device, p_name)));
    }

    @panic("Failed to get global vtable lock");
}

export fn VkLayerLurk_GetInstanceProcAddr
(
    instance: vk.Instance,
    p_name: [*:0]const u8
)
callconv(vk.vulkan_call_conv) vk.PfnVoidFunction
{
    const span_name = std.mem.span(p_name);
    const proc_is_blacklisted =
        overlay_gui.blacklist.is_this_process_blacklisted()
        catch @panic("Failed to validate process blacklist");

    if (proc_is_blacklisted)
    {
        if (!vk_global_state.first_alloc_complete)
        {
            // allocate much less memory for only the basics
            vk_global_state.first_alloc_complete = true;
            vk_global_state.heap_buf = std.heap.c_allocator.create([1024*64]u8) catch @panic("oom");
            vk_global_state.heap_fba = std.heap.FixedBufferAllocator.init(vk_global_state.heap_buf);

            vk_global_state.device_backing = vkt.DeviceDataHashMap.init(vk_global_state.heap_fba.allocator());
            vk_global_state.device_backing.ensureTotalCapacity(8) catch @panic("oom");
            vk_global_state.instance_backing = vkt.InstanceDataHashMap.init(vk_global_state.heap_fba.allocator());
            vk_global_state.instance_backing.ensureTotalCapacity(8) catch @panic("oom");
            std.log.scoped(.VKLURK).debug("Post minimal backing alloc: {d}", .{ vk_global_state.heap_fba.end_index });
        }

        const bl_func = BlacklistRegistionFunctionMap.get(span_name);
        if (bl_func != null) return bl_func.?;
    }
    else
    {
        const inst_func = InstanceRegistionFunctionMap.get(span_name);
        if (inst_func != null) return inst_func.?;

        const device_func = DeviceRegistionFunctionMap.get(span_name);
        if (device_func != null) return device_func.?;
    }

    if (vk_global_state.wrappers_global_lock.tryLock())
    {
        defer vk_global_state.wrappers_global_lock.unlock();
        const instance_data: vkt.InstanceData = vk_global_state.instance_backing.get(instance).?;
        return @ptrCast(@alignCast(instance_data.get_inst_proc_addr_func_ptr(instance, p_name)));
    }

    @panic("Failed to get global vtable lock");
}
