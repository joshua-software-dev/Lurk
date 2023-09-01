const vk = @import("../vk.zig");


const LayerInstanceLink = extern struct {
    p_next: *LayerInstanceLink,
    pfn_next_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
};
const PfnSetInstanceLoaderData = *const fn (vk.Instance, ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Result;
const union_unnamed_1 = extern union {
    p_layer_info: *LayerInstanceLink,
    pfn_set_instance_loader_data: ?PfnSetInstanceLoaderData,
};
const LayerFunction = c_int;
pub const LayerFunction_LAYER_LINK_INFO: c_int = 0;
const LayerFunction_LOADER_DATA_CALLBACK: c_int = 1;
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
const PfnSetDeviceLoaderData = *const fn (vk.Device, ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Result;
const union_unnamed_2 = extern union {
    p_layer_info: *LayerDeviceLink,
    pfn_set_device_loader_data: ?PfnSetDeviceLoaderData,
};
const LayerDeviceCreateInfo = extern struct {
    s_type: vk.StructureType,
    p_next: ?*const anyopaque,
    function: LayerFunction,
    u: union_unnamed_2,
};

pub const LayerInitWrapper = struct
{
    const Self = @This();

    pfn_next_get_device_proc_addr: vk.PfnGetDeviceProcAddr,
    pfn_next_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    pfn_set_device_loader_data: PfnSetDeviceLoaderData,

    pub fn init(p_create_info: *const vk.DeviceCreateInfo) Self
    {
        var next_get_device_proc_addr: ?vk.PfnGetDeviceProcAddr = null;
        var next_get_instance_proc_addr: ?vk.PfnGetInstanceProcAddr = null;
        var set_device_loader_data: ?PfnSetDeviceLoaderData = null;

        var layer_create_info: ?*LayerDeviceCreateInfo = @ptrCast(@alignCast(@constCast(p_create_info.p_next)));

        // step through the chain of p_next until we get to the link info
        while(true)
        {
            if (layer_create_info.?.s_type == vk.StructureType.loader_device_create_info)
            {
                if (layer_create_info.?.function == LayerFunction_LAYER_LINK_INFO)
                {
                    next_get_device_proc_addr = layer_create_info.?.u.p_layer_info.pfn_next_get_device_proc_addr;
                    next_get_instance_proc_addr = layer_create_info.?.u.p_layer_info.pfn_next_get_instance_proc_addr;
                }
                else if (layer_create_info.?.function == LayerFunction_LOADER_DATA_CALLBACK)
                {
                    set_device_loader_data = layer_create_info.?.u.pfn_set_device_loader_data;
                }
            }

            if (layer_create_info.?.p_next == null)
            {
                // move chain on for next layer
                layer_create_info.?.u.p_layer_info = layer_create_info.?.u.p_layer_info.p_next;
                break;
            }

            layer_create_info = @ptrCast(@alignCast(@constCast(layer_create_info.?.p_next)));
        }

        return Self
        {
            .pfn_next_get_device_proc_addr =
                next_get_device_proc_addr orelse @panic("PfnGetDeviceProcAddr is null"),
            .pfn_next_get_instance_proc_addr =
                next_get_instance_proc_addr orelse @panic("PfnGetInstanceProcAddr is null"),
            .pfn_set_device_loader_data =
                set_device_loader_data orelse @panic("PfnSetDeviceLoaderData is null"),
        };
    }
};
