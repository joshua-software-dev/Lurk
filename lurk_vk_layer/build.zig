const std = @import("std");
const download_xml = @import("src/download_xml.zig");


// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void
{
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary
    (
        .{
            .name = "vk_layer_lurk",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        }
    );
    lib.linkLibC();

    const download_file = b.step("download_xml", "Download vk.xml file");
    download_file.makeFn = download_xml.download_xml;
    lib.step.dependOn(download_file);

    const vkzig_dep = b.dependency
    (
        "vulkan_zig",
        .{ .registry = @as([]const u8, b.pathFromRoot("src/vk.xml")) }
    );
    lib.addModule("vulkan-zig", vkzig_dep.module("vulkan-zig"));

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
}
