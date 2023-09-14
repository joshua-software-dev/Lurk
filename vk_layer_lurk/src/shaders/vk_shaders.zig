const std = @import("std");


fn bytes_to_u32_array(comptime string: []const u8) []const u32
{
    @setEvalBranchQuota(1500);
    comptime var out: [@divFloor(string.len, 4) + if (@mod(string.len, 4) > 0) 1 else 0]u32 = undefined;
    var stream = std.io.fixedBufferStream(string);
    var reader = stream.reader();

    var i = 0;
    while (true)
    {
        var buf: [4]u8 = undefined;
        switch (reader.read(&buf) catch unreachable)
        {
            0 => break,
            1 =>
            {
                buf[1] = 0;
                buf[2] = 0;
                buf[3] = 0;
            },
            2 =>
            {
                buf[2] = 0;
                buf[3] = 0;
            },
            3 =>
            {
                buf[3] = 0;
            },
            4 => {},
            else => unreachable
        }

        out[i] = std.mem.readIntNative(u32, &buf);
        i += 1;
    }

    return &out;
}

pub const overlay_frag_spv: []const u32 = bytes_to_u32_array(@embedFile("lurk.frag.spv"));
pub const overlay_vert_spv: []const u32 = bytes_to_u32_array(@embedFile("lurk.vert.spv"));
