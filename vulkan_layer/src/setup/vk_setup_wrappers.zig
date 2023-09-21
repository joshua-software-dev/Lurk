const std = @import("std");

const vk_global_state = @import("vk_global_state.zig");
const vkl = @import("vk_layer_stubs.zig");
const vkt = @import("vk_types.zig");

const vk = @import("vk");


pub fn create_instance_wrappers
(
    p_create_info: *const vk.InstanceCreateInfo,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_instance: *vk.Instance,
)
?vkt.InstanceData
{
    // Ensure this is a nullable pointer (?*) to allow stepping through the
    // chain of p_next
    var layer_create_info: ?*vkl.LayerInstanceCreateInfo =
        @ptrCast(@alignCast(@constCast(p_create_info.p_next)));

    // step through the chain of p_next until we get to the link info
    while
    (
        layer_create_info != null and
        (
            layer_create_info.?.s_type != vk.StructureType.loader_instance_create_info or
            layer_create_info.?.function != vkl.LayerFunction_LAYER_LINK_INFO
        )
    )
    {
        layer_create_info = @ptrCast(@alignCast(@constCast(layer_create_info.?.p_next)));
    }

    if(layer_create_info == null)
    {
        // No loader instance create info
        return null;
    }

    // create non-null pointer variable to make further interactions with this
    // type easier
    var final_lci: *vkl.LayerInstanceCreateInfo = layer_create_info.?;

    const get_inst_proc_addr_func_ptr = final_lci.u.p_layer_info.pfn_next_get_instance_proc_addr;
    const create_instance_func_ptr: vk.PfnCreateInstance =
        @constCast
        (
            @ptrCast
            (
                @alignCast
                (
                    get_inst_proc_addr_func_ptr(.null_handle, "vkCreateInstance")
                )
            )
        );

    // move chain on for next layer
    final_lci.u.p_layer_info = final_lci.u.p_layer_info.p_next;

    // Create instance before loading instance function table
    const create_instance_result = create_instance_func_ptr
    (
        p_create_info,
        p_allocator,
        p_instance,
    );
    if (create_instance_result != vk.Result.success) return null;

    const instance = p_instance.*;
    const instance_wrapper = vkt.LayerInstanceWrapper.load
    (
        instance,
        get_inst_proc_addr_func_ptr,
    )
    catch @panic("Failed to load Vulkan Instance function table 2.");

    std.log.scoped(.VKLURK).debug("Current Instance Ref: {d}", .{ vk_global_state.instance_ref_count });
    vk_global_state.instance_ref_count += 1;
    std.log.scoped(.VKLURK).debug("New Instance Ref: {d}|{d}", .{ vk_global_state.instance_ref_count, instance });
    return vkt.InstanceData
    {
        .instance_id = vk_global_state.instance_ref_count,
        .instance = instance,
        .get_inst_proc_addr_func_ptr = get_inst_proc_addr_func_ptr,
        .instance_wrapper = instance_wrapper,
        .physical_devices = vkt.PhysicalDeviceBacking.init(0) catch @panic("oom"),
    };
}

fn search_device_create_info(p_create_info: *const vk.DeviceCreateInfo, func_type: c_int) *vkl.LayerDeviceCreateInfo
{
    var layer_create_info: ?*vkl.LayerDeviceCreateInfo = @ptrCast(@alignCast(@constCast(p_create_info.p_next)));

    while
    (
        layer_create_info != null and
        (
            layer_create_info.?.s_type != vk.StructureType.loader_device_create_info or
            layer_create_info.?.function != func_type
        )
    )
    {
        layer_create_info = @ptrCast(@alignCast(@constCast(layer_create_info.?.p_next)));
    }

    if(layer_create_info == null)
    {
        @panic("No loader instance create info");
    }

    return layer_create_info.?;
}

pub fn create_device_wrappers
(
    physical_device: vk.PhysicalDevice,
    p_create_info: *const vk.DeviceCreateInfo,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_device: *vk.Device
)
*vkt.DeviceData
{
    var layer_create_info = search_device_create_info(p_create_info, vkl.LayerFunction_LAYER_LINK_INFO);
    const get_device_proc_addr = layer_create_info.u.p_layer_info.pfn_next_get_device_proc_addr;
    const get_inst_proc_addr = layer_create_info.u.p_layer_info.pfn_next_get_instance_proc_addr;
    var create_device_func: vk.PfnCreateDevice = @ptrCast
    (
        get_inst_proc_addr
        (
            vk.Instance.null_handle,
            vk.InstanceCommandFlags.cmdName(.createDevice),
        ),
    );

    layer_create_info.u.p_layer_info = layer_create_info.u.p_layer_info.p_next;

    const create_device_result = create_device_func
    (
        physical_device,
        p_create_info,
        p_allocator,
        p_device,
    );
    if (create_device_result != vk.Result.success) @panic("Vulkan function call failed: Instance.CreateDevice");

    const device = p_device.*;
    const device_wrapper = vkt.LayerDeviceWrapper.load(device, get_device_proc_addr)
    catch @panic("Failed to load Vulkan Device function table.");

    var device_loader = search_device_create_info(p_create_info, vkl.LayerFunction_LOADER_DATA_CALLBACK);
    var backing = vk_global_state.device_backing.getOrPut(device) catch @panic("oom");
    if (backing.found_existing)
    {
        @panic("Found an existing Device with the same id when creating a new one");
    }

    std.log.scoped(.VKLURK).debug("Current Device Ref: {d}", .{ vk_global_state.device_ref_count });
    vk_global_state.device_ref_count += 1;
    std.log.scoped(.VKLURK).debug("New Device Ref: {d}|{d}", .{ vk_global_state.device_ref_count, device });
    backing.value_ptr.* = vkt.DeviceData
    {
        .device_id = vk_global_state.device_ref_count,
        .device = device,
        .physical_device = physical_device,
        .get_device_proc_addr_func = get_device_proc_addr,
        .set_device_loader_data_func = device_loader.u.pfn_set_device_loader_data.?,
        .graphic_queue = null,
        .queues = vkt.VkQueueDataBacking.init(0) catch @panic("oom"),
        .previous_draw_data = null,
        .device_wrapper = device_wrapper,
    };

    return backing.value_ptr;
}
