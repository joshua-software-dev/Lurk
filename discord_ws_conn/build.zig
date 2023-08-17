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

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    b.modules.put
    (
        "discord_ws_conn",
        create_module(b, "", .{ .target = target, .optimize = optimize })
    )
    catch @panic("Failed to add module 'discord_ws_conn' to builder.");
}
