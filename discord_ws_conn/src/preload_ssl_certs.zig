const std = @import("std");


const CLOUDFLARE_CERT_SUBJECT: []const u8 = &.{
    0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04,
    0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x19, 0x30,
    0x17, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x10,
    0x43, 0x6c, 0x6f, 0x75, 0x64, 0x66, 0x6c, 0x61,
    0x72, 0x65, 0x2c, 0x20, 0x49, 0x6e, 0x63, 0x2e,
    0x31, 0x20, 0x30, 0x1e, 0x06, 0x03, 0x55, 0x04,
    0x03, 0x13, 0x17, 0x43, 0x6c, 0x6f, 0x75, 0x64,
    0x66, 0x6c, 0x61, 0x72, 0x65, 0x20, 0x49, 0x6e,
    0x63, 0x20, 0x45, 0x43, 0x43, 0x20, 0x43, 0x41,
    0x2d, 0x33,
};
const CYBERTRUST_CERT_SUBJECT: []const u8 = &.{
    0x31, 0x0b, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04,
    0x06, 0x13, 0x02, 0x49, 0x45, 0x31, 0x12, 0x30,
    0x10, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x09,
    0x42, 0x61, 0x6c, 0x74, 0x69, 0x6d, 0x6f, 0x72,
    0x65, 0x31, 0x13, 0x30, 0x11, 0x06, 0x03, 0x55,
    0x04, 0x0b, 0x13, 0x0a, 0x43, 0x79, 0x62, 0x65,
    0x72, 0x54, 0x72, 0x75, 0x73, 0x74, 0x31, 0x22,
    0x30, 0x20, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13,
    0x19, 0x42, 0x61, 0x6c, 0x74, 0x69, 0x6d, 0x6f,
    0x72, 0x65, 0x20, 0x43, 0x79, 0x62, 0x65, 0x72,
    0x54, 0x72, 0x75, 0x73, 0x74, 0x20, 0x52, 0x6f,
    0x6f, 0x74,
};
pub const START_CERT_BUFFER_SIZE = 4096;

pub fn preload_ssl_certs
(
    temp_allocator: std.mem.Allocator,
    final_allocator: std.mem.Allocator,
)
!std.crypto.Certificate.Bundle
{
    var out_buffer = try std.ArrayList(u8).initCapacity(temp_allocator, START_CERT_BUFFER_SIZE);
    defer out_buffer.deinit();
    var out_indices: [2]u32 = .{ START_CERT_BUFFER_SIZE, START_CERT_BUFFER_SIZE, };

    {
        var temp_bundle: std.crypto.Certificate.Bundle = .{};
        try temp_bundle.map.ensureUnusedCapacityContext(temp_allocator, 256, .{ .cb = &temp_bundle });
        defer temp_bundle.deinit(temp_allocator);
        try temp_bundle.rescan(temp_allocator);

        var cf_cert_start = temp_bundle.find(CLOUDFLARE_CERT_SUBJECT);
        var ct_cert_start = temp_bundle.find(CYBERTRUST_CERT_SUBJECT);

        var val_it = temp_bundle.map.valueIterator();
        var temp_list: []u32 = try temp_allocator.dupe(u32, val_it.items[0..val_it.len]);
        defer temp_allocator.free(temp_list);
        std.sort.block(u32, temp_list, {}, std.sort.asc(u32));

        if (cf_cert_start) |cf_start|
        {
            if (std.mem.indexOfScalar(u32, temp_list, cf_start)) |cf_cert_start_index|
            {
                const next_cert_start =
                    if (cf_cert_start_index + 1 < temp_list.len)
                        temp_list[cf_cert_start_index + 1]
                    else
                        null;

                const cf_cert_bytes =
                    if (next_cert_start != null)
                        temp_bundle.bytes.items[cf_start..next_cert_start.?]
                    else
                        temp_bundle.bytes.items[cf_start..];

                out_indices[0] = @truncate(out_buffer.items.len);
                try out_buffer.appendSlice(cf_cert_bytes);
            }
        }

        if (ct_cert_start) |ct_start|
        {
            if (std.mem.indexOfScalar(u32, temp_list, ct_start)) |ct_cert_start_index|
            {
                const next_cert_start =
                    if (ct_cert_start_index + 1 < temp_list.len)
                        temp_list[ct_cert_start_index + 1]
                    else
                        null;

                const ct_cert_bytes =
                    if (next_cert_start != null)
                        temp_bundle.bytes.items[ct_start..next_cert_start.?]
                    else
                        temp_bundle.bytes.items[ct_start..];

                out_indices[1] = @truncate(out_buffer.items.len);
                try out_buffer.appendSlice(ct_cert_bytes);
            }
        }
    }

    var final_bundle: std.crypto.Certificate.Bundle = .{};
    try final_bundle.bytes.appendSlice(final_allocator, out_buffer.items);

    const now_sec = std.time.timestamp();
    if (out_indices[0] < START_CERT_BUFFER_SIZE)
    {
        try final_bundle.parseCert(final_allocator, out_indices[0], now_sec);
    }
    if (out_indices[1] < START_CERT_BUFFER_SIZE)
    {
        try final_bundle.parseCert(final_allocator, out_indices[1], now_sec);
    }

    return final_bundle;
}
