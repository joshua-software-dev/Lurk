const std = @import("std");

const BlacklistedProcessesMap = std.ComptimeStringMap
(
    void,
    .{
        // shamelessly stolen (under MIT License) from mangohud
        .{ "Amazon Games UI.exe", void, },
        .{ "Battle.net.exe", void, },
        .{ "BethesdaNetLauncher.exe", void, },
        .{ "EpicGamesLauncher.exe", void, },
        .{ "IGOProxy.exe", void, },
        .{ "IGOProxy64.exe", void, },
        .{ "Origin.exe", void, },
        .{ "OriginThinSetupInternal.exe", void, },
        .{ "steam", void, },
        .{ "steamwebhelper", void, },
        .{ "vrcompositor", void, },
        .{ "gldriverquery", void, },
        .{ "vulkandriverquery", void, },
        .{ "Steam.exe", void, },
        .{ "ffxivlauncher.exe", void, },
        .{ "ffxivlauncher64.exe", void, },
        .{ "LeagueClient.exe", void, },
        .{ "LeagueClientUxRender.exe", void, },
        .{ "SocialClubHelper.exe", void, },
        .{ "EADesktop.exe", void, },
        .{ "EALauncher.exe", void, },
        .{ "StarCitizen_Launcher.exe", void, },
        .{ "InsurgencyEAC.exe", void, },
        .{ "GalaxyClient.exe", void, },
        .{ "REDprelauncher.exe", void, },
        .{ "REDlauncher.exe", void, },
        .{ "gamescope", void, },
        .{ "RSI Launcher.exe", void, },
        .{ "tabtip.exe", void, },
        .{ "steam.exe", void, },
        .{ "wine64-preloader", void, },
        .{ "explorer.exe", void, },
        .{ "wine-preloader", void, },
        .{ "iexplore.exe", void, },
        .{ "rundll32.exe", void, },
    },
);

fn get_process_name(buf: []u8) ![]const u8
{
    var proc_name = try std.fs.selfExePath(buf);

    const is_wine =
        std.mem.endsWith(u8, proc_name, "wine-preloader") or
        std.mem.endsWith(u8, proc_name, "wine64-preloader");
    if (!is_wine) return std.fs.path.basename(proc_name);

    const comm_file = try std.fs.openFileAbsolute("/proc/self/comm", .{});
    defer comm_file.close();
    const read_num1 = try comm_file.readAll(buf);
    const possible_exe_name = std.mem.trim(u8, buf[0..read_num1], " \t\r\n");
    if (std.mem.endsWith(u8, possible_exe_name, ".exe")) return possible_exe_name;

    const cmd = try std.fs.openFileAbsolute("/proc/self/cmdline", .{});
    defer cmd.close();
    var last_byte_after_null_byte: usize = 0;
    var i: usize = 0;
    var end_pos = try cmd.getEndPos();
    while (i < end_pos) : (i += 1) // this reads from a list of null byte delimited command line arguments
    {
        try cmd.reader().skipUntilDelimiterOrEof('\x00');

        var next_byte = cmd.reader().readByte()
            catch |err| switch (err)
            {
                error.EndOfStream => return "", // failed to find .exe name
                else => return err,
            };
        i += 1;

        if (next_byte == '\x00')
        {
            try cmd.seekTo(last_byte_after_null_byte);
            const read_num2 = try cmd.read(buf[0..i - last_byte_after_null_byte]);
            return std.fs.path.basenameWindows(buf[0..read_num2]);
        }

        last_byte_after_null_byte = i;
    }

    return "";
}

var stored_result: ?bool = null;
pub fn is_this_process_blacklisted() !bool
{
    if (stored_result != null) return stored_result.?;

    var buf: [1024]u8 = undefined;
    const proc_name = try get_process_name(@constCast(&buf));
    stored_result = BlacklistedProcessesMap.has(proc_name);
    std.log.scoped(.OVERLAY).debug("proc_name: {s} | in blacklist: {}", .{ proc_name, stored_result.? });
    return stored_result.?;
}
