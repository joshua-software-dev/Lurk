const std = @import("std");


const CLOUDFLARE_CERT_SUBJECT: []const u8 = &[_]u8
{
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
const CYBERTRUST_CERT_SUBJECT: []const u8 = &[_]u8
{
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
pub const MAX_CERT_BUNDLE_SIZE = 4096;

pub fn preload_ssl_certs(allocator: std.mem.Allocator) !std.crypto.Certificate.Bundle
{
    var out_buffer = try std.BoundedArray(u8, MAX_CERT_BUNDLE_SIZE).init(0);
    var out_indices: [2]u32 = [2]u32{ out_buffer.buffer.len, out_buffer.buffer.len, };

    {
        var temp_bundle = std.crypto.Certificate.Bundle{};
        defer temp_bundle.deinit(allocator);
        try temp_bundle.rescan(allocator);

        var cf_cert_start = temp_bundle.find(CLOUDFLARE_CERT_SUBJECT);
        var ct_cert_start = temp_bundle.find(CYBERTRUST_CERT_SUBJECT);

        var val_it = temp_bundle.map.valueIterator();
        var temp_list: []u32 = try allocator.dupe(u32, val_it.items[0..val_it.len]);
        defer allocator.free(temp_list);
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

                out_indices[0] = out_buffer.len;
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

                out_indices[1] = out_buffer.len;
                try out_buffer.appendSlice(ct_cert_bytes);
            }
        }
    }

    var final_bundle = std.crypto.Certificate.Bundle{};
    try final_bundle.bytes.appendSlice(allocator, out_buffer.constSlice());

    const now_sec = std.time.timestamp();
    if (out_indices[0] < out_buffer.buffer.len)
    {
        try final_bundle.parseCert(allocator, out_indices[0], now_sec);
    }
    if (out_indices[1] < out_buffer.buffer.len)
    {
        try final_bundle.parseCert(allocator, out_indices[1], now_sec);
    }

    return final_bundle;
}
