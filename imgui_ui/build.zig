const std = @import("std");

const GitRepoStep = @import("src/GitRepoStep.zig");


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

    const cimgui_repo = GitRepoStep.create
    (
        b,
        .{
            .url = "https://github.com/cimgui/cimgui.git",
            .branch = "docking_inter",
            .sha = "a21e28e74027796d983f8c8d4a639a4e304251f2",
            .fetch_enabled = true,
        },
    );

    const cimgui = b.addStaticLibrary
    (
        .{
            .name = "cimgui",
            .target = target,
            .optimize = optimize,
        }
    );
    cimgui.force_pic = true;
    if (target.getCpuArch() == .x86)
    {
        cimgui.link_z_notext = true;
    }
    cimgui.step.dependOn(&cimgui_repo.step);

    cimgui.linkLibC();
    cimgui.linkLibCpp();

    const imguiSources = &[_][]const u8
    {
        "deps/cimgui.git/cimgui.cpp",
        "deps/cimgui.git/imgui/imgui.cpp",
        "deps/cimgui.git/imgui/imgui_demo.cpp",
        "deps/cimgui.git/imgui/imgui_draw.cpp",
        "deps/cimgui.git/imgui/imgui_tables.cpp",
        "deps/cimgui.git/imgui/imgui_widgets.cpp",
    };
    for (imguiSources) |src|
    {
        cimgui.addCSourceFile(.{ .file = .{ .path = src }, .flags = &[_][]const u8{ "-std=c++17" }, });
    }

    const lib = b.addStaticLibrary
    (
        .{
            .name = "imgui_ui",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        }
    );
    lib.addIncludePath(.{ .path = "deps/cimgui/" });
    lib.linkLibrary(cimgui);

    _ = b.addModule
    (
        "imgui_ui",
        .{
            .source_file = .{ .path = "src/main.zig" },
        }
    );

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
}
