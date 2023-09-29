const builtin = @import("builtin");
const std = @import("std");


fn start_0110(req: *std.http.Client.Request, args: anytype) !void
{
    _ = args;
    try req.start();
}

fn start_0120(req: *std.http.Client.Request, args: anytype) !void
{
    try req.start(args);
}

const start_func =
    if (builtin.zig_version.order(std.SemanticVersion.parse("0.11.0") catch unreachable) == .gt)
        start_0120
    else
        start_0110;

// Parts of the following are adapted from software with the following license

// MIT License

// Copyright (c) 2023 Cascade Operating System

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

fn runExternalBinary(allocator: std.mem.Allocator, args: []const []const u8, cwd: ?[]const u8) !void
{
    var child = std.ChildProcess.init(args, allocator);
    if (cwd) |current_working_dir| child.cwd = current_working_dir;

    child.cwd = cwd orelse null;

    try child.spawn();
    const term = try child.wait();

    switch (term)
    {
        .Exited => |code| if (code != 0) return error.UncleanExit,
        else => return error.UncleanExit,
    }
}

fn downloadWithHttpClient(allocator: std.mem.Allocator, url: []const u8, writer: anytype) !void
{
    const uri = try std.Uri.parse(url);

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var headers = std.http.Headers{ .allocator = allocator };
    defer headers.deinit();

    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();

    try start_func(&req, .{});
    try req.wait();

    if (req.response.status != .ok) return error.ResponseNotOk;

    var buffer: [4096]u8 = undefined;

    while (true)
    {
        const number_read = try req.reader().read(&buffer);
        if (number_read == 0) break;
        try writer.writeAll(buffer[0..number_read]);
    }
}

fn fetch(step: *std.Build.Step, url: []const u8, destination_path: []const u8) !void
{
    const file = try std.fs.cwd().createFile(destination_path, .{});
    defer file.close();

    var buffered_writer = std.io.bufferedWriter(file.writer());

    downloadWithHttpClient(step.owner.allocator, url, buffered_writer.writer()) catch |err|
    {
        return step.fail("failed to fetch '{s}': {s}", .{ url, @errorName(err) });
    };

    try buffered_writer.flush();

    // var failed = false;

    // // try curl
    // runExternalBinary(
    //     step.owner.allocator,
    //     &.{
    //         "curl",
    //         "-s", // silent
    //         "-f", // fail fast
    //         "-o",
    //         destination_path,
    //         url,
    //     },
    //     null,
    // ) catch {
    //     failed = true;
    // };

    // if (!failed) return;
    // failed = false;

    // // try wget
    // runExternalBinary(
    //     step.owner.allocator,
    //     &.{
    //         "wget",
    //         "-q", // quiet
    //         "-O",
    //         destination_path,
    //         url,
    //     },
    //     null,
    // ) catch {};

    // if (!failed) return;
    // failed = false;

    // return step.fail("failed to fetch '{s}' using either curl or wget", .{url});
}

pub fn download_xml(self: *std.build.Step, progress: *std.Progress.Node) !void
{
    _ = progress;
    const xml_path = @as([]const u8, self.owner.pathFromRoot("zig-cache/vk.xml"));

    var file_exists = true;
    std.fs.accessAbsolute(xml_path, .{}) catch { file_exists = false; };
    if (!file_exists)
    {
        try fetch
        (
            self, "https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/main/xml/vk.xml",
            xml_path
        );
    }
}
