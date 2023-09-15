const std = @import("std");


pub fn BoundedArrayHashMap(comptime K: type, comptime V: type, comptime buffer_capacity: usize) type
{
    return struct
    {
        const Self = @This();
        const KeyBackingArray = std.BoundedArray(K, buffer_capacity);
        const ValueBackingArray = std.BoundedArray(V, buffer_capacity);

        key_backing_buffer: KeyBackingArray,
        value_backing_buffer: ValueBackingArray,

        pub fn init(initial_capacity: usize) !Self
        {
            return Self
            {
                .key_backing_buffer = try KeyBackingArray.init(initial_capacity),
                .value_backing_buffer = try ValueBackingArray.init(initial_capacity),
            };
        }

        pub fn put(self: *Self, key: K, value: V) !void
        {
            for (self.key_backing_buffer.constSlice()) |k| if (k == key) return error.KeyAlreadyExists;

            self.key_backing_buffer.appendAssumeCapacity(key);
            self.value_backing_buffer.appendAssumeCapacity(value);
        }

        pub fn get(self: *Self, key: K) ?*V
        {
            for (self.key_backing_buffer.constSlice(), 0..) |k, i|
            {
                if (k == key) return &self.value_backing_buffer.slice()[i];
            }

            return null;
        }

        pub fn get_and_remove(self: *Self, key: K) ?V
        {
            for (self.key_backing_buffer.constSlice(), 0..) |k, i|
            {
                if (k == key)
                {
                    _ = self.key_backing_buffer.orderedRemove(i);
                    return self.value_backing_buffer.orderedRemove(i);
                }
            }

            return null;
        }

        pub fn length(self: *Self) usize
        {
            return @intCast(self.key_backing_buffer.len);
        }
    };
}


pub fn get_hash_map_required_bytes(comptime K: type, comptime V: type, comptime buffer_capacity: u32) usize
{
    const Header = struct {
        values: [*]V,
        keys: [*]K,
        capacity: u32,
    };

    const header_align = @alignOf(Header);
    const key_align = if (@sizeOf(K) == 0) 1 else @alignOf(K);
    const val_align = if (@sizeOf(V) == 0) 1 else @alignOf(V);
    const max_align = comptime @max(header_align, key_align, val_align);

    const align_of_metadata = 1;
    _ = align_of_metadata;
    const size_of_metadata = 1;

    const meta_size = @sizeOf(Header) + buffer_capacity * size_of_metadata;

    const keys_start = std.mem.alignForward(usize, meta_size, key_align);
    const keys_end = keys_start + buffer_capacity * @sizeOf(K);

    const vals_start = std.mem.alignForward(usize, keys_end, val_align);
    const vals_end = vals_start + buffer_capacity * @sizeOf(V);

    return std.mem.alignForward(usize, vals_end, max_align);
}
