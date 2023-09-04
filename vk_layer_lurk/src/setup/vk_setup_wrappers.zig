const vk_global_state = @import("vk_global_state.zig");
const vkl = @import("vk_layer_stubs.zig");
const vkt = @import("vk_types.zig");

const vk = @import("../vk.zig");


pub fn create_instance_wrappers
(
    p_create_info: *const vk.InstanceCreateInfo,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_instance: *vk.Instance,
)
void
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
        return;
    }

    // create non-null pointer variable to make further interactions with this
    // type easier
    var final_lci: *vkl.LayerInstanceCreateInfo = layer_create_info.?;

    // use `vulkan-zig`'s handy dandy function table struct to save some function tables
    vk_global_state.base_wrapper = vkt.LayerBaseWrapper.load
    (
        final_lci.u.p_layer_info.pfn_next_get_instance_proc_addr,
    )
    catch @panic("Failed to load Vulkan Instance function table 1.");

    // move chain on for next layer
    final_lci.u.p_layer_info = final_lci.u.p_layer_info.p_next;

    // Create instance before loading instance function table
    const create_instance_result = vk_global_state.base_wrapper.?.dispatch.vkCreateInstance
    (
        p_create_info,
        p_allocator,
        p_instance,
    );
    if (create_instance_result != vk.Result.success) return;

    vk_global_state.instance_wrapper = vkt.LayerInstanceWrapper.load
    (
        p_instance.*,
        vk_global_state.base_wrapper.?.dispatch.vkGetInstanceProcAddr,
    )
    catch @panic("Failed to load Vulkan Instance function table 2.");
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
void
{
    var layer_create_info = search_device_create_info(p_create_info, vkl.LayerFunction_LAYER_LINK_INFO);

    vk_global_state.instance_wrapper.?.dispatch.vkGetDeviceProcAddr =
        layer_create_info.u.p_layer_info.pfn_next_get_device_proc_addr;

    layer_create_info.u.p_layer_info = layer_create_info.u.p_layer_info.p_next;

    const create_device_result = vk_global_state.instance_wrapper.?.dispatch.vkCreateDevice
    (
        physical_device,
        p_create_info,
        p_allocator,
        p_device,
    );
    if (create_device_result != vk.Result.success) @panic("Vulkan function call failed: Instance.CreateDevice");

    const device_wrapper = vkt.LayerDeviceWrapper.load
    (
        p_device.*,
        vk_global_state.instance_wrapper.?.dispatch.vkGetDeviceProcAddr,
    )
    catch @panic("Failed to load Vulkan Device function table.");

    var device_loader = search_device_create_info(p_create_info, vkl.LayerFunction_LOADER_DATA_CALLBACK);
    vk_global_state.device_backing.push
    (
        vkt.DeviceData
        {
            .device = p_device.*,
            .set_device_loader_data_func = device_loader.u.pfn_set_device_loader_data.?,
            .graphic_queue = null,
            .previous_draw_data = null,
            .device_wrapper = device_wrapper,
            .device_queues = vkt.QueueDataBacking.init(0) catch @panic("oom"),
            .swapchain_backing = vkt.SwapchainDataQueue.init(0) catch @panic("oom"),
        }
    )
    catch @panic("oom");
}
