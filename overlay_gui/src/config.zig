const std = @import("std");

const overlay_types = @import("overlay_types.zig");
const state = @import("overlay_state.zig");

const known_folders = @import("known-folders");
const yaml = @import("yaml");


fn expand_path(allocator: std.mem.Allocator, input: []const u8) ![]const u8
{
    if (input.len < 1 or input[0] != '~') return input;

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    return try std.fs.path.join
    (
        allocator,
        &.{
            home,
            if (input.len > 1 and input[1] == '/') input[2..] else input[1..],
        }
    );
}

pub fn make_or_fetch_config(allocator: ?std.mem.Allocator) !overlay_types.overlay_config
{
    if (state.config != null) return state.config.?;

    var arena = std.heap.ArenaAllocator.init(allocator.?);
    defer arena.deinit();

    const config_file_fd = blk: {
        var maybe_path = try known_folders.getPath(arena.allocator(), .local_configuration);
        if (maybe_path == null) return error.FailedToFindConfig;
        const config_folder_path = maybe_path.?;
        defer arena.allocator().free(config_folder_path);

        const lurk_config_folder_path = try std.fs.path.join
        (
            arena.allocator(),
            &.{
                config_folder_path,
                "lurk",
            }
        );
        defer arena.allocator().free(lurk_config_folder_path);

        std.fs.makeDirAbsolute(lurk_config_folder_path)
            catch |err| switch (err)
            {
                error.PathAlreadyExists => {},
                else => return err,
            };

        const lurk_config_path = try std.fs.path.join
        (
            arena.allocator(),
            &.{
                lurk_config_folder_path,
                "lurk_config.yaml",
            }
        );
        defer arena.allocator().free(lurk_config_path);

        break :blk try std.fs.createFileAbsolute(lurk_config_path, .{ .read = true, .truncate = false, });
    };

    const file_info = try config_file_fd.stat();
    if (file_info.size == 0)
    {
        try config_file_fd.writeAll(@embedFile("default_config.yaml"));
        try config_file_fd.seekTo(0);
    }

    {
        var yaml_reader = blk: {
            const config_text = try config_file_fd.readToEndAlloc(arena.allocator(), std.math.maxInt(usize));
            defer arena.allocator().free(config_text);
            config_file_fd.close();

            break :blk try yaml.Yaml.load(arena.allocator(), config_text);
        };
        defer yaml_reader.deinit();

        const config_version = yaml_reader.docs.items[0].map.get("config_version").?;
        const screen_margin = yaml_reader.docs.items[0].map.get("screen_margin").?;
        const window_position = yaml_reader.docs.items[0].map.get("window_position").?;
        const english_only = yaml_reader.docs.items[0].map.get("english_only").?;
        const load_fonts_in_background_thread = yaml_reader.docs.items[0].map.get("load_fonts_in_background_thread").?;
        const primary_font_path = yaml_reader.docs.items[0].map.get("primary_font_path").?;
        const primary_font_size = yaml_reader.docs.items[0].map.get("primary_font_size").?;
        const emoji_font_path = yaml_reader.docs.items[0].map.get("emoji_font_path").?;
        const emoji_font_size = yaml_reader.docs.items[0].map.get("emoji_font_size").?;
        const use_background_network_thread = yaml_reader.docs.items[0].map.get("use_background_network_thread").?;

        const primary_font_realpath = blk2: {
            const expand = try expand_path(arena.allocator(), primary_font_path.string);
            defer arena.allocator().free(expand);
            break :blk2 try std.fs.realpathAlloc(arena.allocator(), expand);
        };
        defer arena.allocator().free(primary_font_realpath);

        const emoji_font_realpath = blk3: {
            const expand = try expand_path(arena.allocator(), emoji_font_path.string);
            defer arena.allocator().free(expand);
            break :blk3 try std.fs.realpathAlloc(arena.allocator(), expand);
        };
        defer arena.allocator().free(emoji_font_realpath);

        const true_false_map = std.ComptimeStringMap
        (
            bool,
            .{
                .{ "true", true, },
                .{ "false", false, },
            }
        );

        state.config = .{
            .config_version = @intCast(config_version.int),
            .screen_margin = @intCast(screen_margin.int),
            .window_position = std.meta.stringToEnum(overlay_types.window_position, window_position.string).?,
            .english_only =
                true_false_map.get(english_only.string) orelse return error.InvalidValue,
            .load_fonts_in_background_thread =
                true_false_map.get(load_fonts_in_background_thread.string) orelse return error.InvalidValue,
            .primary_font_path = try std.BoundedArray(u8, std.fs.MAX_PATH_BYTES - 1).fromSlice(primary_font_realpath),
            .primary_font_size = @floatCast(primary_font_size.float),
            .emoji_font_path = try std.BoundedArray(u8, std.fs.MAX_PATH_BYTES - 1).fromSlice(emoji_font_realpath),
            .emoji_font_size = @floatCast(emoji_font_size.float),
            .use_background_network_thread =
                true_false_map.get(use_background_network_thread.string) orelse return error.InvalidValue,
        };
    }

    return state.config.?;
}
