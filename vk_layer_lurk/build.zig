const std = @import("std");

const download_xml = @import("src/download_xml.zig");

const discws_create = @import("deps/discord_ws_conn/create_mod.zig");
const zgui = @import("deps/zgui/build.zig");


fn find_existing_or_generate_new_vulkan_bindings(b: *std.Build, lib: *std.build.Step.Compile) void
{
    const LOCAL_VULKAN_PATH = @as([]const u8, b.pathFromRoot("src/vk.xml"));
    const SYSTEM_VULKAN_PATH = "/usr/share/vulkan/registry/vk.xml";
    const OUTPUT_VULKAN_PATH = @as([]const u8, b.pathFromRoot("src/vk.zig"));

    var found_generated_vk_bindings = true;
    std.fs.accessAbsolute(OUTPUT_VULKAN_PATH, .{})
    catch { found_generated_vk_bindings = false; };
    if (!found_generated_vk_bindings)
    {
        const vk_gen = b.dependency("vulkan_zig", .{}).artifact("generator");
        const gen_cmd = b.addRunArtifact(vk_gen);

        var found_system_vulkan = true;
        std.fs.accessAbsolute(SYSTEM_VULKAN_PATH, .{})
        catch { found_system_vulkan = false; };

        if (found_system_vulkan)
        {
            gen_cmd.addArg(SYSTEM_VULKAN_PATH);
        }
        else
        {
            const download_file = b.step("download_xml", "Download vk.xml file");
            download_file.makeFn = download_xml.download_xml;
            gen_cmd.step.dependOn(download_file);
            gen_cmd.addArg(LOCAL_VULKAN_PATH);
        }

        const write_files = b.addWriteFiles();
        write_files.addCopyFileToSource(gen_cmd.addOutputFileArg(OUTPUT_VULKAN_PATH), "src/vk.zig");

        write_files.step.dependOn(&gen_cmd.step);
        lib.step.dependOn(&write_files.step);
    }
}

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

    const disc = discws_create.create_module(b, "deps/discord_ws_conn/", .{ .target = target, .optimize = optimize, });

    const zgui_pkg = zgui.package
    (
        b,
        target,
        optimize,
        .{
            .options = .{ .backend = .no_backend }
        }
    );

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
    lib.force_pic = true;
    if (target.getCpuArch() == .x86)
    {
        lib.link_z_notext = true;
    }

    lib.addModule("discord_ws_conn", disc);

    lib.linkLibC();
    find_existing_or_generate_new_vulkan_bindings(b, lib);
    zgui_pkg.link(lib);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    const install = b.addInstallArtifact(lib, .{});
    install.dest_dir = .prefix;
    install.dest_sub_path = b.fmt
    (
        "{s}/{s}",
        .{
            switch (target.getCpuArch())
            {
                .x86 => "lib32",
                .x86_64 => "lib64",
                else => @panic("Unsupported CPU architecture.")
            },
            lib.out_filename
        }
    );

    b.default_step.dependOn(&install.step);
    b.installDirectory
    (
        .{
            .source_dir = .{ .path = "manifests/package" },
            .install_dir = .prefix,
            .install_subdir = "share/vulkan/implicit_layer.d/"
        }
    );

    b.installFile("../LICENSE", "share/licenses/lurk/LICENSE");
    b.installDirectory
    (
        .{
            .source_dir = .{ .path = "third_party" },
            .install_dir = .prefix,
            .install_subdir = "share/licenses/lurk/third_party"
        }
    );
    b.installDirectory
    (
        .{
            .source_dir = .{ .path = "../third_party" },
            .install_dir = .prefix,
            .install_subdir = "share/licenses/lurk/third_party"
        }
    );
}
