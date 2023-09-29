const std = @import("std");


pub const CertBundleSettings = union(enum)
{
    /// This allocator is used to load the full system cert bundle, which will
    /// then be trimmed down to just certs required to communicate with
    /// discord's API. Lots of memory churn, recommend against using a
    /// FixedBufferAllocator. All memory from this allocator will be freed and
    /// just the smaller bundle will be retained using the final_cert_allocator
    allocate_new: std.mem.Allocator,
    use_existing: std.crypto.Certificate.Bundle,
};

pub const StdHttpSettings = struct
{
    /// The primary allocator used for holding interrim messages and processing
    /// data. When null, a fixed size buffer will be obtained using the
    /// state_allocator instead.
    message_allocator: ?std.mem.Allocator,
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
