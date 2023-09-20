const std = @import("std");

const hacks = @import("dlsym_hacks.zig");

const zgl = @import("zgl");


pub extern fn ImGui_ImplOpenGL3_Init(glsl_version: ?[*:0]const u8) bool;
pub extern fn ImGui_ImplOpenGL3_Shutdown() void;
pub extern fn ImGui_ImplOpenGL3_NewFrame() void;
pub extern fn ImGui_ImplOpenGL3_RenderDrawData(draw_data: *const anyopaque) void;

const OpenGlLoadFunction = fn (name: [*:0]const u8) ?zgl.binding.FunctionPointer;
const Pfn_glXCreateContext = fn(?*anyopaque, ?*anyopaque, ?*anyopaque, i32) callconv(.C) ?*anyopaque;
const Pfn_glXCreateContextAttribs = fn(?*anyopaque, ?*anyopaque, ?*anyopaque, i32, [*c]const i32) callconv(.C) ?*anyopaque;
const Pfn_glXCreateContextAttribsARB = fn(?*anyopaque, ?*anyopaque, ?*anyopaque, i32, [*c]const i32) callconv(.C) ?*anyopaque;
const Pfn_glXDestroyContext = fn(?*anyopaque, ?*anyopaque) callconv(.C) void;
const Pfn_glXGetCurrentContext = fn() callconv(.C) ?*anyopaque;
const Pfn_glXGetSwapIntervalMESA = fn() callconv(.C) i32;
const Pfn_glXMakeCurrent = fn(?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.C) i32;
const Pfn_glXQueryDrawable = fn (?*anyopaque, ?*anyopaque, i32, [*c]u32) i32;
const Pfn_glXSwapBuffers = fn(?*anyopaque, ?*anyopaque) callconv(.C) void;
const Pfn_glXSwapBuffersMscOML = fn(?*anyopaque, ?*anyopaque, i64, i64, i64) callconv(.C) i64;
const Pfn_glXSwapIntervalEXT = fn(?*anyopaque, ?*anyopaque, i32) callconv(.C) void;
const Pfn_glXSwapIntervalMESA = fn(u32) callconv(.C) i32;
const Pfn_glXSwapIntervalSGI = fn(i32) callconv(.C) i32;

pub var CreateContext: ?*Pfn_glXCreateContext = null;
pub var CreateContextAttribs: ?*Pfn_glXCreateContextAttribs = null;
pub var CreateContextAttribsARB: ?*Pfn_glXCreateContextAttribsARB = null;
pub var DestroyContext: ?*Pfn_glXDestroyContext = null;
pub var GetCurrentContext: ?*Pfn_glXGetCurrentContext = null;
pub var GetProcAddress: ?*OpenGlLoadFunction = null;
pub var GetProcAddressARB: ?*OpenGlLoadFunction = null;
pub var GetSwapIntervalMESA: ?*Pfn_glXGetSwapIntervalMESA = null;
pub var MakeCurrent: ?*Pfn_glXMakeCurrent = null;
pub var QueryDrawable: ?*Pfn_glXQueryDrawable = null;
pub var SwapBuffers: ?*Pfn_glXSwapBuffers = null;
pub var SwapBuffersMscOML: ?*Pfn_glXSwapBuffersMscOML = null;
pub var SwapIntervalEXT: ?*Pfn_glXSwapIntervalEXT = null;
pub var SwapIntervalMESA: ?*Pfn_glXSwapIntervalMESA = null;
pub var SwapIntervalSGI: ?*Pfn_glXSwapIntervalSGI = null;

pub var opengl_load_complete = false;

fn load_pointer_table(arb: bool, name: [:0]const u8) ?zgl.binding.FunctionPointer
{
    if (arb) return GetProcAddressARB.?(name);
    return GetProcAddress.?(name);
}

pub fn dynamic_load_opengl(arb: bool) void
{
    std.log.scoped(.GLLURK).debug("Something loaded our OpenGL functions", .{});
    if (opengl_load_complete) @panic("Tried to dlopen opengl more than once!");

    if (!hacks.functions_loaded)
    {
        std.log.scoped(.GLLURK).warn("dlsym was not hooked, trying to hook from opengl loader", .{});
        hacks.get_original_func_ptrs() catch @panic("Failed to hook dlopen/dlsym");
    }

    const opengl_lib = hacks.original_dlopen_func_ptr.?("libGL.so.1", hacks.RTLD_LAZY);

    GetProcAddress = @ptrCast(@alignCast(hacks.original_dlsym_func_ptr.?(opengl_lib, "glXGetProcAddress")));
    if (GetProcAddress == null) @panic("Failed to get glXGetProcAddress pointer");

    GetProcAddressARB = @ptrCast(@alignCast(hacks.original_dlsym_func_ptr.?(opengl_lib, "glXGetProcAddressARB")));
    if (GetProcAddressARB == null) @panic("Failed to get glXGetProcAddressARB pointer");

    const manual_loader = if (arb) GetProcAddressARB.? else GetProcAddress.?;

    CreateContext = @ptrCast(@constCast(manual_loader("glXCreateContext")));
    if (CreateContext == null) @panic("Failed to get glXCreateContext pointer");

    // its ok for these to fail
    CreateContextAttribs = @ptrCast(@constCast(manual_loader("glXCreateContextAttribs")));
    CreateContextAttribsARB = @ptrCast(@constCast(manual_loader("glXCreateContextAttribsARB")));

    DestroyContext = @ptrCast(@constCast(manual_loader("glXDestroyContext")));
    if (DestroyContext == null) @panic("Failed to get glXDestroyContext pointer");

    GetCurrentContext = @ptrCast(@constCast(manual_loader("glXGetCurrentContext")));
    if (GetCurrentContext == null) @panic("Failed to get glXGetCurrentContext pointer");

    SwapBuffers = @ptrCast(@constCast(manual_loader("glXSwapBuffers")));
    if (SwapBuffers == null) @panic("Failed to get glXSwapBuffers pointer");

    // its ok for this to fail
    SwapBuffersMscOML = @ptrCast(@constCast(manual_loader("glXSwapBuffersMscOML")));

    SwapIntervalEXT = @ptrCast(@constCast(manual_loader("glXSwapIntervalEXT")));
    if (SwapIntervalEXT == null) @panic("Failed to get glXSwapIntervalEXT pointer");

    SwapIntervalSGI = @ptrCast(@constCast(manual_loader("glXSwapIntervalSGI")));
    if (SwapIntervalSGI == null) @panic("Failed to get glXSwapIntervalSGI pointer");

    SwapIntervalMESA = @ptrCast(@constCast(manual_loader("glXSwapIntervalMESA")));
    if (SwapIntervalMESA == null) @panic("Failed to get glXSwapIntervalMESA pointer");

    GetSwapIntervalMESA = @ptrCast(@constCast(manual_loader("glXGetSwapIntervalMESA")));
    if (GetSwapIntervalMESA == null) @panic("Failed to get glXGetSwapIntervalMESA pointer");

    QueryDrawable = @ptrCast(@constCast(manual_loader("glXQueryDrawable")));
    if (QueryDrawable == null) @panic("Failed to get glXQueryDrawable pointer");

    MakeCurrent = @ptrCast(@constCast(manual_loader("glXMakeCurrent")));
    if (MakeCurrent == null) @panic("Failed to get glXMakeCurrent pointer");

    zgl.loadExtensions(arb, load_pointer_table) catch @panic("Failed to load opengl context");
    opengl_load_complete = true;
    std.log.scoped(.GLLURK).debug("Finished loading our OpenGL functions", .{});
}
