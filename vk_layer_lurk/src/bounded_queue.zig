const std = @import("std");


pub fn BoundedQueue(comptime T: type, comptime buffer_capacity: usize) type
{
    return struct
    {
        const Self = @This();
        const BoundedBackingArray = std.BoundedArray(T, buffer_capacity);

        backing_buffer: BoundedBackingArray,

        pub fn init(initial_capacity: usize) !Self
        {
            return Self { .backing_buffer = try BoundedBackingArray.init(initial_capacity) };
        }

        pub fn push(self: *Self, item: T) !void
        {
            try self.backing_buffer.resize(self.backing_buffer.len);
            try self.backing_buffer.insert(0, item);
        }

        pub fn pop(self: *Self) ?T
        {
            return self.backing_buffer.popOrNull();
        }

        pub fn peek_head(self: *Self) ?*T
        {
            if (self.backing_buffer.len < 1) return null;
            return &self.backing_buffer.slice()[0];
        }

        pub fn peek_tail(self: *Self) ?*T
        {
            if (self.backing_buffer.len < 1) return null;
            return &self.backing_buffer.slice()[self.backing_buffer.len - 1];
        }
    };
}
