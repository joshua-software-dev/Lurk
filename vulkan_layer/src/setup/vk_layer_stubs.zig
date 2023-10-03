const vk = @import("vk");


const LayerInstanceLink = extern struct {
    p_next: *LayerInstanceLink,
    pfn_next_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
};
const PfnSetInstanceLoaderData = *const fn (vk.Instance, u64) callconv(vk.vulkan_call_conv) vk.Result;
const union_unnamed_1 = extern union {
    p_layer_info: *LayerInstanceLink,
    pfn_set_instance_loader_data: ?PfnSetInstanceLoaderData,
};
const LayerFunction = c_int;
pub const LayerFunction_LAYER_LINK_INFO: c_int = 0;
pub const LayerFunction_LOADER_DATA_CALLBACK: c_int = 1;
pub const LayerInstanceCreateInfo = extern struct {
    s_type: vk.StructureType,
    p_next: ?*const anyopaque,
    function: LayerFunction,
    u: union_unnamed_1,
};

const LayerDeviceLink = extern struct {
    p_next: *LayerDeviceLink,
    pfn_next_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    pfn_next_get_device_proc_addr: vk.PfnGetDeviceProcAddr,
};
pub const PfnSetDeviceLoaderData = *const fn (vk.Device, u64) callconv(vk.vulkan_call_conv) vk.Result;
const union_unnamed_2 = extern union {
    p_layer_info: *LayerDeviceLink,
    pfn_set_device_loader_data: ?PfnSetDeviceLoaderData,
};
pub const LayerDeviceCreateInfo = extern struct {
    s_type: vk.StructureType,
    p_next: ?*const anyopaque,
    function: LayerFunction,
    u: union_unnamed_2,
};
