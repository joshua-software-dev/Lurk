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

    const zgl_dep = b.dependency("zgl", .{});

    const elfhacks = b.addStaticLibrary
    (
        .{
            .name = "elfhacks",
            .target = target,
            .optimize = optimize,
        }
    );
    elfhacks.force_pic = true;
    elfhacks.linkLibCpp();
    if (target.getCpuArch() == .x86)
    {
        elfhacks.link_z_notext = true;
    }

    elfhacks.addCSourceFile
    (
        .{
            .file = .{ .path = "deps/elfhacks/elfhacks.cpp" },
            .flags = &[_][]const u8
            {
                "-std=c++17",
                "-fno-sanitize=undefined",
                "-fvisibility=hidden",
            },
        }
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
    cimgui.linkLibC();

    cimgui.addIncludePath(.{ .path = "../imgui_ui/deps/cimgui.git/" });
    cimgui.addIncludePath(.{ .path = "../imgui_ui/deps/cimgui.git/imgui/" });
    cimgui.addIncludePath(.{ .path = "deps/imgui/" });

    const imguiSources = &[_][]const u8
    {
        "../imgui_ui/deps/cimgui.git/cimgui.cpp",
        "../imgui_ui/deps/cimgui.git/imgui/imgui.cpp",
        "../imgui_ui/deps/cimgui.git/imgui/imgui_demo.cpp",
        "../imgui_ui/deps/cimgui.git/imgui/imgui_draw.cpp",
        "../imgui_ui/deps/cimgui.git/imgui/imgui_tables.cpp",
        "../imgui_ui/deps/cimgui.git/imgui/imgui_widgets.cpp",
        "deps/imgui/imgui_impl_opengl3.cpp",
    };
    for (imguiSources) |src|
    {
        cimgui.addCSourceFile
        (
            .{
                .file = .{ .path = src },
                .flags = &[_][]const u8
                {
                    "-std=c++17",
                    "-fno-sanitize=undefined",
                    "-fvisibility=hidden",
                },
            }
        );
    }

    const lib = b.addSharedLibrary(.{
        .name = "gl_layer_lurk",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.force_pic = true;
    if (target.getCpuArch() == .x86)
    {
        lib.link_z_notext = true;
    }

    lib.linkLibrary(cimgui);
    lib.linkLibrary(elfhacks);
    lib.addModule("zgl", zgl_dep.module("zgl"));

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
