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

    const clap = b.dependency("clap", .{ .target = target, .optimize = optimize });
    // const disc = b.anonymousDependency
    // (
    //     "discord_ws_conn",
    //     @import("discord_ws_conn/build.zig"),
    //     .{ .target = target, .optimize = optimize }
    // );
    // // Eventually, the below section can be replaced with the above, but for
    // // now the package manager doesn't manage transient dependencies at all.
    // ===BEGIN SECTION===
    const iguanaTLS = b.dependency("iguanaTLS", .{ .target = target, .optimize = optimize });
    const uuid = b.dependency("uuid", .{ .target = target, .optimize = optimize });
    const ws = b.dependency("ws", .{ .target = target, .optimize = optimize });
    const ziglyph = b.dependency("ziglyph", .{ .target = target, .optimize = optimize });

    const disc = b.addModule
    (
        "discord_ws_conn",
        .{
            .source_file = .{ .path = "discord_ws_conn/src/main.zig" },
            .dependencies = &.{
                .{ .name = "iguanaTLS", .module = iguanaTLS.module("iguanaTLS") },
                .{ .name = "uuid", .module = uuid.module("uuid") },
                .{ .name = "ws", .module = ws.module("ws") },
                .{ .name = "ziglyph", .module = ziglyph.module("ziglyph") },
            }
        },
    );
    // ====END SECTION====

    const exe = b.addExecutable
    (
        .{
            .name = "lurk",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        }
    );
    exe.pie = true;
    // exe.addModule("discord_ws_conn", disc.module("discord_ws_conn"));
    exe.addModule("discord_ws_conn", disc);
    exe.addModule("clap", clap.module("clap"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    b.installFile("lurk.service", "lib/systemd/user/lurk.service");
    b.installFile("LICENSE", "share/licenses/lurk/LICENSE");
    b.installDirectory
    (
        .{
            .source_dir = .{ .path = "third_party" },
            .install_dir = .prefix,
            .install_subdir = "share/licenses/lurk/third_party"
        }
    );

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
