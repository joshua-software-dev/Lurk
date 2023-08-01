const std = @import("std");

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

    const iguanaTLS = b.dependency("iguanaTLS", .{ .target = target, .optimize = optimize });
    const uuid = b.dependency("uuid", .{ .target = target, .optimize = optimize });
    const ws = b.dependency("ws", .{ .target = target, .optimize = optimize });
    const ziglyph = b.dependency("ziglyph", .{ .target = target, .optimize = optimize });

    _ = b.addModule
    (
        "discord_ws_conn",
        .{
            .source_file = .{ .path = "src/discord_ws_conn/main.zig" },
            .dependencies = &.{
                .{ .name = "iguanaTLS", .module = iguanaTLS.module("iguanaTLS") },
                .{ .name = "uuid", .module = uuid.module("uuid") },
                .{ .name = "ws", .module = ws.module("ws") },
                .{ .name = "ziglyph", .module = ziglyph.module("ziglyph") },
            }
        },
    );
}
