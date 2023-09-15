const vk = @import("../vk.zig");

pub var physical_mem_props: ?vk.PhysicalDeviceMemoryProperties = null;


pub fn vk_memory_type(properties: vk.MemoryPropertyFlags, type_bits: u32) u32
{
    if (physical_mem_props) |props|
    {
        var i: u32 = 0;
        var supported_mem_type: u32 = 1;
        while (i < props.memory_type_count) : ({i += 1; supported_mem_type += supported_mem_type;})
        {
            if
            (
                props.memory_types[i].property_flags.contains(properties)
                and ((type_bits & supported_mem_type) > 0)
            )
            {
                return i;
            }
        }

        @panic("Unable to find memory type");
    }

    @panic("Physical memory properties are null!");
}
