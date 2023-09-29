const builtin = @import("builtin");
const std = @import("std");

const gl_load = @import("gl_load.zig");
const hacks = @import("dlsym_hacks.zig");
const state = @import("state.zig");

const overlay_gui = @import("overlay_gui");
const zgl = @import("zgl");


// Zig scoped logger set based on compile mode
pub const std_options = struct
{
    pub const log_scope_levels: []const std.log.ScopeLevel =
    &[_]std.log.ScopeLevel
    {
        .{
            .scope = .GLLURK,
            .level = switch (builtin.mode)
            {
                .Debug => .debug,
                else => .info,
            }
        },
        .{
            .scope = .OVERLAY,
            .level = switch (builtin.mode)
            {
                .Debug => .debug,
                else => .info,
            }
        },
        .{
            .scope = .WS,
            .level = switch (builtin.mode)
            {
                .Debug => .debug,
                else => .info,
            }
        },
    };
};

const HookedFunctionMap = std.ComptimeStringMap
(
    ?*anyopaque,
    .{
        .{
            "glXGetProcAddressARB",
            @as(?*anyopaque, @ptrCast(@constCast(&glXGetProcAddressARB))),
        },
        .{
            "glXGetProcAddress",
            @as(?*anyopaque, @ptrCast(@constCast(&glXGetProcAddress))),
        },
        .{
            "glXCreateContext",
            @as(?*anyopaque, @ptrCast(@constCast(&glXCreateContext))),
        },
        .{
            "glXCreateContextAttribs",
            @as(?*anyopaque, @ptrCast(@constCast(&glXCreateContextAttribs))),
        },
        .{
            "glXCreateContextAttribsARB",
            @as(?*anyopaque, @ptrCast(@constCast(&glXCreateContextAttribsARB))),
        },
        .{
            "glXDestroyContext",
            @as(?*anyopaque, @ptrCast(@constCast(&glXDestroyContext))),
        },
        .{
            "glXSwapBuffers",
            @as(?*anyopaque, @ptrCast(@constCast(&glXSwapBuffers))),
        },
        .{
            "glXSwapBuffersMscOML",
            @as(?*anyopaque, @ptrCast(@constCast(&glXSwapBuffersMscOML))),
        },
    },
);

fn process_is_blacklisted() bool
{
    if (gl_load.opengl_load_complete and state.is_using_zink == null)
    {
        const renderer = zgl.getString(.renderer);
        if (renderer == null)
        {
            std.log.scoped(.GLLURK).warn("Failed to get opengl renderer name, continuing may fail.", .{});
            state.is_using_zink = false;
        }
        else if (std.mem.indexOf(u8, renderer.?, "zink") != null)
        {
            // Prefer using the vulkan layer instead of gl when running under zink
            state.is_using_zink = true;
        }
        else
        {
            state.is_using_zink = false;
        }
    }

    if (state.is_using_zink != null and state.is_using_zink.?) return true;
    return overlay_gui.blacklist.is_this_process_blacklisted()
        catch @panic("Failed to validate process blacklist");
}

fn create_imgui_context() void
{
    if (!process_is_blacklisted())
    {
        state.imgui_ref_count = @truncate(state.imgui_ref_count + 1);

        if (builtin.mode == .Debug) overlay_gui.set_allocator_for_imgui(null);

        overlay_gui.load_fonts(true);

        const allocator = state.get_default_allocator();

        // Internal logic makes connecting multiple times idempotent
        overlay_gui.disch.start_discord_conn(allocator)
        catch @panic("Failed to start discord connection.");

        var viewport: [4]i32 = undefined;
        zgl.binding.getIntegerv(zgl.binding.VIEWPORT, viewport[0..]);

        overlay_gui.create_overlay_context(@floatFromInt(viewport[2]), @floatFromInt(viewport[3]));

        const old_ctx = overlay_gui.use_overlay_context() catch unreachable;
        defer overlay_gui.restore_old_context(old_ctx);
    }
}

fn do_imgui_swap() void
{
    if (state.imgui_ref_count < 1) return;

    const old_ctx = overlay_gui.use_overlay_context() catch return;
    defer overlay_gui.restore_old_context(old_ctx);

    overlay_gui.is_draw_ready()
        catch |err|
            switch (err)
            {
                error.FontNotLoaded => return,
                error.FontTextureRequiresReload =>
                {
                    _ = gl_load.ImGui_ImplOpenGL3_Init(null);
                    return;
                },
            };

    var viewport: [4]i32 = undefined;
    zgl.binding.getIntegerv(zgl.binding.VIEWPORT, viewport[0..]);

    gl_load.ImGui_ImplOpenGL3_NewFrame();
    overlay_gui.draw_frame(@intCast(viewport[2]), @intCast(viewport[3]))
        catch @panic("Unexpected error while drawing frame");

    gl_load.ImGui_ImplOpenGL3_RenderDrawData(overlay_gui.get_draw_data().?);
    state.first_draw_complete = true;
}

export fn dlsym(handle: ?*anyopaque, name: [*c]const u8) ?*anyopaque
{
    if (!hacks.functions_loaded)
    {
        hacks.get_original_func_ptrs() catch |err| std.debug.panic("Encountered error while loading: {any}", .{ err });
        hacks.functions_loaded = true;
    }

    const span_name = std.mem.span(name);
    std.log.scoped(.GLLURK).debug("dlsym: {s}", .{ span_name });
    const hook = HookedFunctionMap.get(span_name);
    if (hook != null) return hook.?;

    return hacks.original_dlsym_func_ptr.?(handle, name);
}

export fn glXGetProcAddress(procedure_name: [*c]const u8) ?*anyopaque
{
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);

    const span_name = std.mem.span(procedure_name);
    const hook = HookedFunctionMap.get(span_name);
    if (hook != null) return hook.?;

    return @constCast(gl_load.GetProcAddress.?(procedure_name));
}

export fn glXGetProcAddressARB(procedure_name: [*c]const u8) ?*anyopaque
{
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(true);

    const span_name = std.mem.span(procedure_name);
    const hook = HookedFunctionMap.get(span_name);
    if (hook != null) return hook.?;

    return @constCast(gl_load.GetProcAddressARB.?(procedure_name));
}

export fn glXCreateContext(dpy: ?*anyopaque, vis: ?*anyopaque, share_list: ?*anyopaque, arg_direct: i32) ?*anyopaque
{
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);

    const result = gl_load.CreateContext.?(dpy, vis, share_list, arg_direct);
    if (result != null and state.imgui_ref_count < 1) create_imgui_context();
    return result;
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
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);

    const result = gl_load.CreateContextAttribs.?(dpy, config, share_context, direct, attrib_list);
    if (result != null and state.imgui_ref_count < 1) create_imgui_context();
    return result;
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
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);

    const result = gl_load.CreateContextAttribsARB.?(dpy, config, share_context, direct, arg_attrib_list);
    if (result != null and state.imgui_ref_count < 1) create_imgui_context();
    return result;
}

export fn glXDestroyContext(dpy: ?*anyopaque, ctx: ?*anyopaque) void
{
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    gl_load.DestroyContext.?(dpy, ctx);

    const temp_ref_count: i64 = state.imgui_ref_count - 1;
    // (abs(x) + x) / 2
    // branchless negative number to 0 formula
    state.imgui_ref_count = @truncate
    (
        @divExact
        (
            (std.math.absInt(temp_ref_count) catch unreachable) + temp_ref_count,
            2
        )
    );

    if (state.imgui_ref_count == 0)
    {
        if (state.first_draw_complete)
        {
            gl_load.ImGui_ImplOpenGL3_Shutdown();
            overlay_gui.destroy_overlay_context();
            state.free_default_allocator();
        }

        overlay_gui.disch.stop_discord_conn();
    }
}

export fn glXSwapBuffers(dpy: ?*anyopaque, drawable: ?*anyopaque) void
{
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    if (gl_load.GetCurrentContext.?() != null and state.imgui_ref_count < 1) create_imgui_context();

    do_imgui_swap();
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
    if (!gl_load.opengl_load_complete) gl_load.dynamic_load_opengl(false);
    if (gl_load.GetCurrentContext.?() != null and state.imgui_ref_count < 1) create_imgui_context();

    do_imgui_swap();
    return gl_load.SwapBuffersMscOML.?(dpy, drawable, target_msc, divisor, remainder);
}
