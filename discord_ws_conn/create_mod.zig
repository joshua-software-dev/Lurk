const std = @import("std");

pub fn create_module(builder: *std.Build, comptime path_to_module: []const u8, args: anytype) *std.build.Module
{
    const uuid = builder.dependency("uuid", args);
    const ws = builder.dependency("ws", args);
    const ziglyph = builder.dependency("ziglyph", args);

    const source_path =
        std.fs.path.join(builder.allocator, &.{ path_to_module, "src/main.zig" })
        catch @panic("Failed to combine paths.");

    return builder.createModule
    (
        .{
            .source_file = .{ .path = source_path },
            .dependencies = &.{
                .{ .name = "uuid", .module = uuid.module("uuid") },
                .{ .name = "ws", .module = ws.module("ws") },
                .{ .name = "ziglyph", .module = ziglyph.module("ziglyph") },
            }
        },
    );
}
