const vk_layer_stubs = @import("vk_layer_stubs.zig");
const vk_global_state = @import("vk_global_state.zig");

const vk = @import("../vk.zig");


pub fn create_instance_wrappers(p_create_info: *const vk.InstanceCreateInfo, p_instance: *vk.Instance) void
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
        return;
    }

    // create non-null pointer variable to make further interactions with this
    // type easier
    var final_lci: *vk_layer_stubs.LayerInstanceCreateInfo = layer_create_info.?;

    // use `vulkan-zig`'s handy dandy function table struct to save some function tables
    vk_global_state.base_wrapper = vk_global_state.LayerBaseWrapper.load
    (
        final_lci.u.p_layer_info.pfn_next_get_instance_proc_addr,
    )
    catch @panic("Failed to load Vulkan Instance function table 1.");

    vk_global_state.instance_wrapper = vk_global_state.LayerInstanceWrapper.load
    (
        p_instance.*,
        final_lci.u.p_layer_info.pfn_next_get_instance_proc_addr,
    )
    catch @panic("Failed to load Vulkan Instance function table 2.");

    // move chain on for next layer
    final_lci.u.p_layer_info = final_lci.u.p_layer_info.p_next;
}

pub fn create_device_wrappers(p_device: *vk.Device, p_create_info: *const vk.DeviceCreateInfo) void
{
    vk_global_state.init_wrapper = vk_layer_stubs.LayerInitWrapper.init(p_create_info);

    vk_global_state.device_wrapper = vk_global_state.LayerDeviceWrapper.load
    (
        p_device.*,
        vk_global_state.init_wrapper.?.pfn_next_get_device_proc_addr,
    )
    catch @panic("Failed to load Vulkan Device function table.");
}
