const std = @import("std");


pub const CertBundleSettings = union(enum)
{
    allocate_new: struct
    {
        /// An allocator used to load the full system cert bundle, which will then
        /// be trimmed down to just certs required to communicate with discord's API
        temp_cert_allocator: std.mem.Allocator,
    },
    use_existing: std.crypto.Certificate.Bundle,
};

pub const StdHttpSettings = struct
{
    /// The primary allocator used for holding interrim messages and processing
    /// data. When null, a fixed size buffer on the stack will be used instead
    primary_allocator: ?std.mem.Allocator,
    /// The allocator used during http requests to hold temporary data for a
    /// given request
    http_allocator: std.mem.Allocator,
    /// The allocator used to allocate and eventually free the final, smaller
    /// certificate bundle
    final_cert_allocator: std.mem.Allocator,
    bundle: CertBundleSettings,
};

pub const HttpMode = union(enum)
{
    ChildProcess: ?std.mem.Allocator,
    IguanaTLS: ?std.mem.Allocator,
    StdLibraryHttp: StdHttpSettings,
};
