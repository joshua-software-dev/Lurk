const builtin = @import("builtin");
const std = @import("std");

const Elf_Phdr = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: usize,
    p_vaddr: usize,
    p_paddr: usize,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

const Elf_Dyn_Union = extern union {
    d_val: usize,
    d_ptr: usize,
};
const Elf_Dyn = extern struct {
    d_tag: usize,
    d_un: Elf_Dyn_Union,
};

const Elf32_Sym = extern struct {
    st_name: u32,
    st_value: u32,
    st_size: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
};
const Elf64_Sym = extern struct {
    st_name: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
    st_value: u64,
    st_size: u64,
};

const eh_obj_t = extern struct {
    name: [*c]const u8,
    addr: usize,
    phdr: [*c]const Elf_Phdr,
    phnum: u16,
    dynamic: [*c]Elf_Dyn,
    symtab: if (builtin.target.ptrBitWidth() == 32) [*c]Elf32_Sym else [*c]Elf64_Sym,
    strtab: [*c]const u8,
    hash: [*c]u32,
    gnu_hash: [*c]u32,
};

extern fn eh_destroy_obj(obj: [*c]eh_obj_t) c_int;
extern fn eh_find_obj(obj: [*c]eh_obj_t, soname: [*c]const u8) c_int;
extern fn eh_find_sym(obj: [*c]eh_obj_t, name: [*c]const u8, to: [*c]?*anyopaque) c_int;

pub const RTLD_LOCAL: i32 = 0;
pub const RTLD_LAZY: i32 = 1;
pub const RTLD_NOW: i32 = 2;
pub const RTLD_BINDING_MASK: i32 = 3;
pub const RTLD_NOLOAD: i32 = 4;
pub const RTLD_DEEPBIND: i32 = 8;
pub const RTLD_GLOBAL: i32 = 256;
pub const RTLD_NODELETE: i32 = 4096;
pub const RTLD_DEFAULT: ?*anyopaque = @ptrFromInt(0);
pub const RTLD_NEXT: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));

pub var functions_loaded = false;
pub var original_dlopen_func_ptr: ?*fn ([*c]const u8, c_int) align(8) callconv(.C) ?*anyopaque = null;
pub var original_dlsym_func_ptr: ?*fn (?*anyopaque, [*c]const u8) align(8) callconv(.C) ?*anyopaque = null;

pub fn get_original_func_ptrs() !void
{
    std.log.scoped(.GLLURK).debug("Hooking dlopen and dlsym...", .{});

    const dlls_to_try = [_][]const u8{ "*libdl.so*", "*libc.so*", "*libc.*.so*" };
    for (dlls_to_try) |dll|
    {
        var libdl: eh_obj_t = undefined;
        if (eh_find_obj(&libdl, dll.ptr) > 0) // error
        {
            continue;
        }

        original_dlopen_func_ptr = undefined;
        if (eh_find_sym(&libdl, "dlopen", @ptrCast(&original_dlopen_func_ptr.?)) > 0) // error
        {
            original_dlopen_func_ptr = null;
        }

        original_dlsym_func_ptr = undefined;
        if (eh_find_sym(&libdl, "dlsym", @ptrCast(&original_dlsym_func_ptr.?)) > 0) // error
        {
            original_dlsym_func_ptr = null;
        }
        _ = eh_destroy_obj(&libdl);

        if (original_dlopen_func_ptr != null and original_dlsym_func_ptr != null) break;
    }

    if (original_dlopen_func_ptr == null) return error.FailedToFindDlopen;
    if (original_dlsym_func_ptr == null) return error.FailedToFindDlsym;
}


