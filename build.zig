const std = @import("std");

const download_xml = @import("vulkan_layer/src/download_xml.zig");
const GitRepoStep = @import("overlay_gui/src/GitRepoStep.zig");

fn build_cli
(
    builder: *std.Build,
    allow_any_arch: bool,
    clap_dep: *std.Build.Dependency,
    disc: *std.Build.Module,
    args: anytype,
)
void
{
    if (!allow_any_arch)
    {
        switch (args.target.getCpuArch())
        {
            .arm, .aarch64, .riscv64, .x86, .x86_64, => {},
            else => @panic("Unsupported CPU architecture.")
        }
    }

    const lurk_cli = builder.addExecutable
    (
        .{
            .name = "lurk_cli",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = .{ .path = "cli/src/main.zig" },
            .target = args.target,
            .optimize = args.optimize,
        }
    );
    lurk_cli.pie = true;
    lurk_cli.addModule("discord_ws_conn", disc);
    lurk_cli.addModule("clap", clap_dep.module("clap"));

    const target_info = std.zig.system.NativeTargetInfo.detect(args.target) catch @panic("Failed to get target info");

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    const cli_install = builder.addInstallArtifact(lurk_cli, .{});
    cli_install.dest_dir = .prefix;
    switch (target_info.target.ptrBitWidth())
    {
        32 =>
        {
            cli_install.dest_sub_path = builder.fmt("bin/{s}32", .{ lurk_cli.out_filename });
        },
        64 =>
        {
            cli_install.dest_sub_path = builder.fmt("bin/{s}", .{ lurk_cli.out_filename });
        },
        else => @panic("Unsupported CPU architecture."),
    }
    builder.default_step.dependOn(&cli_install.step);

    builder.installFile("cli/lurk.service", "lib/systemd/user/lurk.service");
    builder.installDirectory
    (
        .{
            .source_dir = .{ .path = "cli/third_party" },
            .install_dir = .prefix,
            .install_subdir = "share/licenses/lurk/third_party"
        }
    );

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = builder.addRunArtifact(lurk_cli);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(builder.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (builder.args) |cli_args| {
        run_cmd.addArgs(cli_args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = builder.step("run", "Run the lurk cli implementation");
    run_step.dependOn(&run_cmd.step);
}

fn build_opengl_layer
(
    builder: *std.Build,
    allow_any_arch: bool,
    overlay_gui_lib: *std.Build.Step.Compile,
    overlay_gui_mod: *std.Build.Module,
    zgl_dep: *std.Build.Dependency,
    args: anytype,
)
void
{
    if (!allow_any_arch)
    {
        switch (args.target.getCpuArch())
        {
            .arm => @panic("TODO: Enable this once zig fixes its included arm32 libc"),
            .aarch64, .x86, .x86_64, => {},
            else => @panic("Unsupported CPU architecture.")
        }
    }

    const elfhacks = builder.addStaticLibrary
    (
        .{
            .name = "elfhacks",
            .target = args.target,
            .optimize = args.optimize,
        }
    );
    elfhacks.force_pic = true;
    elfhacks.linkLibCpp();
    if (args.target.getCpuArch() == .x86)
    {
        elfhacks.link_z_notext = true;
    }

    elfhacks.addCSourceFile
    (
        .{
            .file = .{ .path = "opengl_layer/deps/elfhacks/elfhacks.cpp" },
            .flags = &[_][]const u8
            {
                "-std=c++17",
                "-fno-sanitize=undefined",
                "-fvisibility=hidden",
            },
        }
    );

    const opengl_layer = builder.addSharedLibrary
    (
        .{
            .name = "opengl_layer_lurk",
            .root_source_file = .{ .path = "opengl_layer/src/main.zig" },
            .target = args.target,
            .optimize = args.optimize,
        }
    );
    opengl_layer.force_pic = true;
    if (args.target.getCpuArch() == .x86)
    {
        opengl_layer.link_z_notext = true;
    }

    if (args.optimize != .Debug)
    {
        opengl_layer.strip = true;
    }

    opengl_layer.link_function_sections = true;
    opengl_layer.link_gc_sections = true;
    opengl_layer.link_z_relro = true;

    opengl_layer.linkLibrary(elfhacks);
    opengl_layer.linkLibrary(overlay_gui_lib);
    opengl_layer.addModule("overlay_gui", overlay_gui_mod);
    opengl_layer.addModule("zgl", zgl_dep.module("zgl"));

    const target_info = std.zig.system.NativeTargetInfo.detect(args.target) catch @panic("Failed to get target info");

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    const gl_install = builder.addInstallArtifact(opengl_layer, .{});
    gl_install.dest_dir = .prefix;
    switch (target_info.target.ptrBitWidth())
    {
        32 =>
        {
            gl_install.dest_sub_path = builder.fmt("lib32/{s}", .{ opengl_layer.out_filename });
        },
        64 =>
        {
            gl_install.dest_sub_path = builder.fmt("lib/{s}", .{ opengl_layer.out_filename });
        },
        else => @panic("Unsupported CPU architecture."),
    }
    builder.default_step.dependOn(&gl_install.step);

    builder.installDirectory
    (
        .{
            .source_dir = .{ .path = "opengl_layer/third_party" },
            .install_dir = .prefix,
            .install_subdir = "share/licenses/lurk/third_party"
        }
    );
    builder.installFile("opengl_layer/scripts/lurkgl", "bin/lurkgl");
}

fn build_vulkan_layer
(
    builder: *std.Build,
    allow_any_arch: bool,
    overlay_gui_lib: *std.Build.Step.Compile,
    overlay_gui_mod: *std.Build.Module,
    vk_zig_dep: *std.Build.Dependency,
    zglslang_dep: *std.Build.Dependency,
    use_system_vulkan: bool,
    args: anytype,
)
void
{
    if (!allow_any_arch)
    {
        switch (args.target.getCpuArch())
        {
            .arm => @panic("TODO: Enable this once zig fixes its included arm32 libc"),
            .aarch64, .x86, .x86_64, => {},
            else => @panic("Unsupported CPU architecture.")
        }
    }

    const options = builder.addOptions();
    options.addOption(bool, "allow_any_arch", allow_any_arch);

    const LOCAL_VULKAN_PATH: std.Build.LazyPath = .{ .path = builder.pathFromRoot("zig-cache/vk.xml") };
    const SYSTEM_VULKAN_PATH: std.Build.LazyPath = .{ .path = "/usr/share/vulkan/registry/vk.xml" };

    const vk_gen = vk_zig_dep.artifact("generator");
    const gen_cmd = builder.addRunArtifact(vk_gen);

    var found_system_vulkan = true;
    std.fs.accessAbsolute(SYSTEM_VULKAN_PATH.path, .{})
    catch { found_system_vulkan = false; };

    if (found_system_vulkan and use_system_vulkan)
    {
        gen_cmd.addFileArg(SYSTEM_VULKAN_PATH);
    }
    else
    {
        const download_file = builder.step("download_xml", "Download vk.xml file");
        download_file.makeFn = download_xml.download_xml;
        gen_cmd.step.dependOn(download_file);
        gen_cmd.addFileArg(LOCAL_VULKAN_PATH);
    }

    // the "../" in "../zig-cache/vk.zig" is very important, otherwise it ends
    // up in zig-out/zig-cache/vk.zig
    const gen_install = builder.addInstallFile(gen_cmd.addOutputFileArg("vk.zig"), "../zig-cache/vk.zig");
    gen_install.step.dependOn(&gen_cmd.step);

    const zware_glslang = zglslang_dep.artifact("zware_glslang");

    var found_frag_output = true;
    std.fs.accessAbsolute(builder.pathFromRoot("vulkan_layer/src/shaders/lurk.frag.spv"), .{})
    catch { found_frag_output = false; };

    var found_vert_output = true;
    std.fs.accessAbsolute(builder.pathFromRoot("vulkan_layer/src/shaders/lurk.vert.spv"), .{})
    catch { found_vert_output = false; };

    const vulkan_layer = builder.addSharedLibrary
    (
        .{
            .name = "vulkan_layer_lurk",
            .root_source_file = .{ .path = "vulkan_layer/src/main.zig" },
            .target = args.target,
            .optimize = args.optimize,
        }
    );
    vulkan_layer.force_pic = true;
    if (args.target.getCpuArch() == .x86)
    {
        vulkan_layer.link_z_notext = true;
    }

    if (args.optimize != .Debug)
    {
        vulkan_layer.strip = true;
    }

    vulkan_layer.link_function_sections = true;
    vulkan_layer.link_gc_sections = true;
    vulkan_layer.link_z_relro = true;

    if (!found_frag_output)
    {
        const file =
            std.fs.openFileAbsolute(builder.pathFromRoot("vulkan_layer/src/shaders/lurk.frag.glsl"), .{})
            catch @panic("Failed to read lurk.frag.glsl");
        const file_bytes = file.readToEndAlloc(builder.allocator, 4096) catch @panic("oom");
        defer builder.allocator.free(file_bytes);

        const frag_shader_compile = builder.addRunArtifact(zware_glslang);
        var new_stdio = std.ArrayList(std.Build.Step.Run.StdIo.Check)
            .initCapacity(builder.allocator, 1) catch @panic("oom");
        new_stdio.appendAssumeCapacity(.{ .expect_term = .{ .Exited = 0 }});

        frag_shader_compile.setStdIn(.{ .bytes = builder.allocator.dupe(u8, file_bytes) catch @panic("oom") });
        frag_shader_compile.stdio = .{ .check = new_stdio };
        frag_shader_compile.addArgs
        (
            &[_][]const u8
            {
                "--quiet",
                "--stdin",
                "-V",
                "-S",
                "frag",
                "-o",
                "vulkan_layer/src/shaders/lurk.frag.spv",
            }
        );

        vulkan_layer.step.dependOn(&frag_shader_compile.step);
    }

    if (!found_vert_output)
    {
        const file =
            std.fs.openFileAbsolute(builder.pathFromRoot("vulkan_layer/src/shaders/lurk.vert.glsl"), .{})
            catch @panic("Failed to read lurk.vert.glsl");
        const file_bytes = file.readToEndAlloc(builder.allocator, 4096) catch @panic("oom");
        defer builder.allocator.free(file_bytes);

        const vert_shader_compile = builder.addRunArtifact(zware_glslang);
        var new_stdio = std.ArrayList(std.Build.Step.Run.StdIo.Check)
            .initCapacity(builder.allocator, 1) catch @panic("oom");
        new_stdio.appendAssumeCapacity(.{ .expect_term = .{ .Exited = 0 }});

        vert_shader_compile.setStdIn(.{ .bytes = builder.allocator.dupe(u8, file_bytes) catch @panic("oom") });
        vert_shader_compile.stdio = .{ .check = new_stdio };
        vert_shader_compile.addArgs
        (
            &[_][]const u8
            {
                "--quiet",
                "--stdin",
                "-V",
                "-S",
                "vert",
                "-o",
                "vulkan_layer/src/shaders/lurk.vert.spv",
            }
        );

        vulkan_layer.step.dependOn(&vert_shader_compile.step);
    }

    vulkan_layer.step.dependOn(&gen_install.step);
    const vulkan_mod = builder.addModule("vk", .{ .source_file = .{ .path = "zig-cache/vk.zig" } });
    vulkan_layer.addModule("vk", vulkan_mod);

    vulkan_layer.addModule("vulkan_layer_build_options", options.createModule());

    vulkan_layer.addIncludePath(.{ .path = "overlay_gui/dep/cimgui/" });
    vulkan_layer.linkLibrary(overlay_gui_lib);
    vulkan_layer.addModule("overlay_gui", overlay_gui_mod);

    vulkan_layer.linkLibC();

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    const vk_install = builder.addInstallArtifact(vulkan_layer, .{});
    vk_install.dest_dir = .prefix;
    switch (args.target.getCpuArch())
    {
        .arm =>
        {
            vk_install.dest_sub_path = builder.fmt("lib32/{s}", .{ vulkan_layer.out_filename });
            builder.installFile
            (
                "vulkan_layer/manifests/package/vk_layer_lurk_linux_arm_32.json",
                "share/vulkan/implicit_layer.d/vk_layer_lurk_linux_arm_32.json"
            );
        },
        .aarch64 =>
        {
            vk_install.dest_sub_path = builder.fmt("lib/{s}", .{ vulkan_layer.out_filename });
            builder.installFile
            (
                "vulkan_layer/manifests/package/vk_layer_lurk_linux_arm_64.json",
                "share/vulkan/implicit_layer.d/vk_layer_lurk_linux_arm_64.json"
            );
        },
        .x86 =>
        {
            vk_install.dest_sub_path = builder.fmt("lib32/{s}", .{ vulkan_layer.out_filename });
            builder.installFile
            (
                "vulkan_layer/manifests/package/vk_layer_lurk_linux_x86_32.json",
                "share/vulkan/implicit_layer.d/vk_layer_lurk_linux_x86_32.json"
            );
        },
        .x86_64 =>
        {
            vk_install.dest_sub_path = builder.fmt("lib/{s}", .{ vulkan_layer.out_filename });
            builder.installFile
            (
                "vulkan_layer/manifests/package/vk_layer_lurk_linux_x86_64.json",
                "share/vulkan/implicit_layer.d/vk_layer_lurk_linux_x86_64.json"
            );
        },
        else =>
        {
            if(!allow_any_arch) @panic("Unsupported CPU architecture.");

            const target_info = std.zig.system.NativeTargetInfo.detect(args.target)
            catch @panic("Failed to get target info");

            vk_install.dest_sub_path = builder.fmt
            (
                "lib{d}/{s}",
                .{
                    target_info.target.ptrBitWidth(),
                    vulkan_layer.out_filename
                }
            );
        },
    }
    builder.default_step.dependOn(&vk_install.step);

    builder.installDirectory
    (
        .{
            .source_dir = .{ .path = "vulkan_layer/third_party" },
            .install_dir = .prefix,
            .install_subdir = "share/licenses/lurk/third_party"
        }
    );
    builder.installFile("vulkan_layer/scripts/lurkvk", "bin/lurkvk");
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

    const should_build_cli =
        if (b.option(bool, "build_cli", "Build the cli implementation, default=true")) |opt|
            opt
        else
            true;

    const should_build_opengl =
        if (b.option(bool, "build_gl", "Build the opengl layer, default=true")) |opt|
            opt
        else
            true;

    const should_build_vulkan =
        if (b.option(bool, "build_vk", "Build the vulkan layer, default=true")) |opt|
            opt
        else
            true;

    const allow_any_arch =
        if
        (
            b.option
            (
                bool,
                "any_arch",
                "Allow building for any architecture, supported explicitly or not, default=false"
            )
        ) |opt|
            opt
        else
            false;

    const use_system_vulkan = b.option
    (
        bool,
        "sysvk",
        "Use /usr/share/vulkan/registry/vk.xml to generate Vulkan bindings " ++
        "instead of downloading the latest bindings from the Vulkan SDK."
    ) orelse false;

    if (!should_build_cli and !should_build_opengl and !should_build_vulkan) return;

    const build_args = .{ .target = target, .optimize = optimize, };

    const cimgui_repo = GitRepoStep.create
    (
        b,
        .{
            .url = "https://github.com/cimgui/cimgui.git",
            .branch = "docking_inter",
            .sha = "a21e28e74027796d983f8c8d4a639a4e304251f2",
            .fetch_enabled = true,
            .path = b.pathFromRoot("overlay_gui/deps/cimgui"),
        },
    );

    var clap_dep: ?*std.Build.Dependency = null;
    if (should_build_cli)
    {
        clap_dep = b.dependency("clap", build_args);
    }

    var vk_dep: ?*std.Build.Dependency = null;
    if (should_build_vulkan)
    {
        vk_dep = b.dependency("vulkan_zig", .{});
    }

    var zgl_dep: ?*std.Build.Dependency = null;
    if (should_build_opengl)
    {
        zgl_dep = b.dependency("zgl", .{});
    }

    var zglslang_dep: ?*std.Build.Dependency = null;
    if (should_build_vulkan)
    {
        // build with debug for faster build times
        zglslang_dep = b.dependency("zware_glslang", .{ .optimize = .Debug });
    }

    const iguana_tls_dep = b.dependency("iguanaTLS", build_args);
    const uuid_dep = b.dependency("uuid", build_args);
    const ws_dep = b.dependency("ws", build_args);
    const ziglyph_dep = b.dependency("ziglyph", build_args);

    const disc = b.addModule
    (
        "discord_ws_conn",
        .{
            .source_file = .{ .path = "discord_ws_conn/src/main.zig" },
            .dependencies = &.{
                .{ .name = "iguanaTLS", .module = iguana_tls_dep.module("iguanaTLS") },
                .{ .name = "uuid", .module = uuid_dep.module("uuid") },
                .{ .name = "ws", .module = ws_dep.module("ws") },
                .{ .name = "ziglyph", .module = ziglyph_dep.module("ziglyph") },
            },
        }
    );

    if (should_build_cli) build_cli(b, allow_any_arch, clap_dep.?, disc, build_args);

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

    cimgui.linkLibCpp();
    cimgui.addIncludePath(.{ .path = "overlay_gui/deps/cimgui/imgui/" });
    cimgui.addCSourceFiles
    (
        &[_][]const u8
        {
            "overlay_gui/deps/cimgui/cimgui.cpp",
            "overlay_gui/deps/cimgui/imgui/imgui.cpp",
            "overlay_gui/deps/cimgui/imgui/imgui_demo.cpp",
            "overlay_gui/deps/cimgui/imgui/imgui_draw.cpp",
            "overlay_gui/deps/cimgui/imgui/imgui_tables.cpp",
            "overlay_gui/deps/cimgui/imgui/imgui_widgets.cpp",
            "opengl_layer/deps/imgui/imgui_impl_opengl3.cpp",
        },
        &[_][]const u8
        {
            "-std=c++17",
            "-fno-sanitize=undefined",
            "-fvisibility=hidden",
        }
    );

    const overlay_gui_lib = b.addStaticLibrary
    (
        .{
            .name = "overlay_gui",
            .root_source_file = .{ .path = "overlay_gui/src/main.zig" },
            .target = target,
            .optimize = optimize,
        }
    );
    overlay_gui_lib.force_pic = true;
    if (target.getCpuArch() == .x86)
    {
        overlay_gui_lib.link_z_notext = true;
    }
    overlay_gui_lib.addIncludePath(.{ .path = "overlay_gui/deps/cimgui/" });
    overlay_gui_lib.linkLibrary(cimgui);

    const overlay_gui_mod = b.addModule
    (
        "overlay_gui",
        .{
            .source_file = .{ .path = "overlay_gui/src/main.zig" },
            .dependencies = &.{
                .{ .name = "discord_ws_conn", .module = disc },
            }
        }
    );

    if (should_build_opengl)
    {
        build_opengl_layer(b, allow_any_arch, overlay_gui_lib, overlay_gui_mod, zgl_dep.?, build_args);
    }
    if (should_build_vulkan)
    {
        build_vulkan_layer
        (
            b,
            allow_any_arch,
            overlay_gui_lib,
            overlay_gui_mod,
            vk_dep.?,
            zglslang_dep.?,
            use_system_vulkan,
            build_args,
        );
    }

    b.installFile("LICENSE", "share/licenses/lurk/LICENSE");
    b.installDirectory
    (
        .{
            .source_dir = .{ .path = "discord_ws_conn/third_party" },
            .install_dir = .prefix,
            .install_subdir = "share/licenses/lurk/third_party"
        }
    );
}
