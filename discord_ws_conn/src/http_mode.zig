const std = @import("std");


pub const CertBundleSettings = union(enum)
{
    allocate_new: std.mem.Allocator,
    use_existing: std.crypto.Certificate.Bundle,
};

pub const StdHttpSettings = struct
{
    http_allocator: std.mem.Allocator,
    cert_allocator: std.mem.Allocator,
    bundle: CertBundleSettings,
};

pub const HttpMode = union(enum)
{
    ChildProcess,
    IguanaTLS,
    StdLibraryHttp: StdHttpSettings,
};
