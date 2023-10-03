const vk = @import("vk");

const vk_global_state = @import("vk_global_state.zig");
const vkt = @import("vk_types.zig");


pub fn vk_memory_type(device: vk.Device, properties: vk.MemoryPropertyFlags, type_bits: u32) u32
{
    const device_data: vkt.DeviceData = vk_global_state.device_backing.get(device).?;
    const maybe_instance_data: ?vkt.InstanceData = blk: {
        var it = vk_global_state.instance_backing.iterator();
        while (it.next()) |kv|
        {
            for (kv.value_ptr.physical_devices.slice()) |instance_assigned_physical_device|
            {
                if (instance_assigned_physical_device == device_data.physical_device)
                {
                    break :blk kv.value_ptr.*;
                }
            }
        }

        break :blk null;
    };
    const instance_data = maybe_instance_data.?;
    const physical_mem_props = instance_data.instance_wrapper.getPhysicalDeviceMemoryProperties
    (
        device_data.physical_device
    );

    var i: u32 = 0;
    var supported_mem_type: u32 = 1;
    while (i < physical_mem_props.memory_type_count) : ({i += 1; supported_mem_type += supported_mem_type;})
    {
        if
        (
            physical_mem_props.memory_types[i].property_flags.contains(properties)
            and ((type_bits & supported_mem_type) > 0)
        )
        {
            return i;
        }
    }

    @panic("Unable to find memory type");
}
