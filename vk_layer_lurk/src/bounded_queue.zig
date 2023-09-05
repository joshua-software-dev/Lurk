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
