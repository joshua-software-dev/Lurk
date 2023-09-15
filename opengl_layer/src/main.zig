const std = @import("std");
const gl_load = @import("gl_load.zig");
const hacks = @import("dlsym_hacks.zig");

const cimgui = @import("cimgui.zig");
const zgl = @import("zgl");


export fn dlsym(handle: ?*anyopaque, name: [*c]const u8) ?*anyopaque
{
    if (!hacks.functions_loaded)
    {
        hacks.get_original_func_ptrs() catch |err| std.debug.panic("Encountered error while loading: {any}", .{ err });
        hacks.functions_loaded = true;
    }

    std.log.scoped(.HACKS).info("dlsym: {s}", .{ name });

    return hacks.original_dlsym_func_ptr.?(handle, name);
}

export fn glXGetProcAddress(procedure_name: [*c]const u8) ?*anyopaque
{
    std.log.scoped(.GLLOAD).debug("GetProcAddress called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("GetProcAddress finished loading procedures", .{});
    return @constCast(gl_load.GetProcAddress.?(procedure_name));
}

export fn glXGetProcAddressARB(procedure_name: [*c]const u8) ?*anyopaque
{
    std.log.scoped(.GLLOAD).debug("GetProcAddressARB called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(true);
    std.log.scoped(.GLLOAD).debug("GetProcAddressARB finished loading procedures", .{});
    return @constCast(gl_load.GetProcAddressARB.?(procedure_name));
}

export fn glXCreateContext(dpy: ?*anyopaque, vis: ?*anyopaque, share_list: ?*anyopaque, arg_direct: i32) ?*anyopaque
{
    std.log.scoped(.GLLOAD).debug("glXCreateContext called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXCreateContext finished loading procedures", .{});
    return gl_load.CreateContext.?(dpy, vis, share_list, arg_direct);
}

export fn glXCreateContextAttribs
(
    dpy: ?*anyopaque,
    config: ?*anyopaque,
    share_context: ?*anyopaque,
    direct: i32,
    attrib_list: [*c]const i32
)
?*anyopaque
{
    std.log.scoped(.GLLOAD).debug("glXCreateContextAttribs called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXCreateContextAttribs finished loading procedures", .{});
    return gl_load.CreateContextAttribs.?(dpy, config, share_context, direct, attrib_list);
}

export fn glXCreateContextAttribsARB
(
    dpy: ?*anyopaque,
    config: ?*anyopaque,
    share_context: ?*anyopaque,
    direct: i32,
    arg_attrib_list: [*c]const i32
)
?*anyopaque
{
    std.log.scoped(.GLLOAD).debug("glXCreateContextAttribsARB called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXCreateContextAttribsARB finished loading procedures", .{});
    return gl_load.CreateContextAttribsARB.?(dpy, config, share_context, direct, arg_attrib_list);
}

export fn glXDestroyContext(dpy: ?*anyopaque, ctx: ?*anyopaque) void
{
    std.log.scoped(.GLLOAD).debug("glXDestroyContext called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXDestroyContext finished loading procedures", .{});
    gl_load.DestroyContext.?(dpy, ctx);
}

export fn glXMakeCurrent(dpy: ?*anyopaque, drawable: ?*anyopaque, ctx: ?*anyopaque) i32
{
    std.log.scoped(.GLLOAD).debug("glXMakeCurrent called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXMakeCurrent finished loading procedures", .{});
    return gl_load.MakeCurrent.?(dpy, drawable, ctx);
}

var imgui_loaded = false;
var our_imgui_context: [*c]cimgui.ImGuiContext = null;
export fn glXSwapBuffers(dpy: ?*anyopaque, drawable: ?*anyopaque) void
{
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    if (gl_load.GetCurrentContext.?() != null and !imgui_loaded)
    {
        std.log.scoped(.GLLOAD).debug("Started the imgui stuffs", .{});
        imgui_loaded = true;
        const prev_imgui_ctx = cimgui.igGetCurrentContext();
        our_imgui_context = cimgui.igCreateContext(null);
        const io = cimgui.igGetIO();

        var viewport: [4]i32 = undefined;
        zgl.binding.getIntegerv(zgl.binding.VIEWPORT, viewport[0..]);

        io.*.IniFilename = null;
        io.*.DisplaySize = cimgui.ImVec2{ .x = @floatFromInt(viewport[2]), .y = @floatFromInt(viewport[3]), };

        _ = gl_load.ImGui_ImplOpenGL3_Init(null);
        var current_texture: [1]i32 = undefined;
        zgl.binding.getIntegerv(zgl.binding.TEXTURE_BINDING_2D, current_texture[0..]);

        cimgui.igSetCurrentContext(prev_imgui_ctx);
        std.log.scoped(.GLLOAD).debug("Finished the imgui stuffs", .{});
    }

    const prev_imgui_ctx = cimgui.igGetCurrentContext();
    cimgui.igSetCurrentContext(our_imgui_context);

    gl_load.ImGui_ImplOpenGL3_NewFrame();
    cimgui.igNewFrame();
    cimgui.igSeparator();
    cimgui.igSeparator();
    cimgui.igSeparator();
    cimgui.igRender();
    gl_load.ImGui_ImplOpenGL3_RenderDrawData(cimgui.igGetDrawData());
    cimgui.igSetCurrentContext(prev_imgui_ctx);

    gl_load.SwapBuffers.?(dpy, drawable);
}

export fn glXSwapBuffersMscOML
(
    dpy: ?*anyopaque,
    drawable: ?*anyopaque,
    target_msc: i64,
    divisor: i64,
    remainder: i64
)
i64
{
    std.log.scoped(.GLLOAD).debug("glXSwapBuffersMscOML called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXSwapBuffersMscOML finished loading procedures", .{});
    return gl_load.SwapBuffersMscOML.?(dpy, drawable, target_msc, divisor, remainder);
}

export fn glXSwapIntervalEXT(dpy: ?*anyopaque, draw: ?*anyopaque, interval: i32) void
{
    std.log.scoped(.GLLOAD).debug("glXSwapIntervalEXT called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXSwapIntervalEXT finished loading procedures", .{});
    gl_load.SwapIntervalEXT.?(dpy, draw, interval);
}

export fn glXSwapIntervalSGI(interval: i32) i32
{
    std.log.scoped(.GLLOAD).debug("glXSwapIntervalSGI called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXSwapIntervalSGI finished loading procedures", .{});
    return gl_load.SwapIntervalSGI.?(interval);
}

export fn glXSwapIntervalMESA(interval: u32) i32
{
    std.log.scoped(.GLLOAD).debug("glXSwapIntervalMESA called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXSwapIntervalMESA finished loading procedures", .{});
    return gl_load.SwapIntervalMESA.?(interval);
}

export fn glXGetSwapIntervalMESA() i32
{
    std.log.scoped(.GLLOAD).debug("glXGetSwapIntervalMESA called", .{});
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    std.log.scoped(.GLLOAD).debug("glXGetSwapIntervalMESA finished loading procedures", .{});
    return gl_load.GetSwapIntervalMESA.?();
}
