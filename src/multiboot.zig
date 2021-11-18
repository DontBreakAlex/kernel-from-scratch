const elf = @import("elf.zig");
const std = @import("std");
// The format of the Multiboot information structure (as defined so far) follows:
//         +-------------------+
// 0       | flags             |    (required)
//         +-------------------+
// 4       | mem_lower         |    (present if flags[0] is set)
// 8       | mem_upper         |    (present if flags[0] is set)
//         +-------------------+
// 12      | boot_device       |    (present if flags[1] is set)
//         +-------------------+
// 16      | cmdline           |    (present if flags[2] is set)
//         +-------------------+
// 20      | mods_count        |    (present if flags[3] is set)
// 24      | mods_addr         |    (present if flags[3] is set)
//         +-------------------+
// 28 - 40 | syms              |    (present if flags[4] or
//         |                   |                flags[5] is set)
//         +-------------------+
// 44      | mmap_length       |    (present if flags[6] is set)
// 48      | mmap_addr         |    (present if flags[6] is set)
//         +-------------------+
// 52      | drives_length     |    (present if flags[7] is set)
// 56      | drives_addr       |    (present if flags[7] is set)
//         +-------------------+
// 60      | config_table      |    (present if flags[8] is set)
//         +-------------------+
// 64      | boot_loader_name  |    (present if flags[9] is set)
//         +-------------------+
// 68      | apm_table         |    (present if flags[10] is set)
//         +-------------------+
// 72      | vbe_control_info  |    (present if flags[11] is set)
// 76      | vbe_mode_info     |
// 80      | vbe_mode          |
// 82      | vbe_interface_seg |
// 84      | vbe_interface_off |
// 86      | vbe_interface_len |
//         +-------------------+
// 88      | framebuffer_addr  |    (present if flags[12] is set)
// 96      | framebuffer_pitch |
// 100     | framebuffer_width |
// 104     | framebuffer_height|
// 108     | framebuffer_bpp   |
// 109     | framebuffer_type  |
// 110-115 | color_info        |
//         +-------------------+

pub const Flags = packed struct {
    memory: u1,
    boot_dev: u1,
    cmdline: u1,
    mods: u1,
    aout_syms: u1,
    elf_shdr: u1,
    mem_map: u1,
    drive_info: u1,
    config_table: u1,
    boot_loader_name: u1,
    apm_table: u1,
    vbe_info: u1,
    framebuffer_info: u1,
    pad1: u3,
    pad2: u16,
};

const ElfSections = elf.ElfSections;
pub const MultibootInfo = packed struct {
    flags: Flags,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    syms: ElfSections,
    mmap_length: u32,
    mmap_addr: u32,
    drives_length: u32,
    drives_addr: u32,
    config_table: u32,
    boot_loader_name: u32,
    apm_table: u32,
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,
    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
    color_info: u48,
};

pub var MULTIBOOT: *MultibootInfo = undefined;

export fn read_multiboot(ptr: *MultibootInfo) callconv(.C) void {
    MULTIBOOT = ptr;
}

pub const SymbolsError = error{
    NoSymbol,
};

const CStr = [*:0]const u8;
const vga = @import("vga.zig");

pub fn loadSymbols() !void {
    // TODO: Validate size
    const section_names = MULTIBOOT.syms.addr[MULTIBOOT.syms.shndx];
    const symbol_section = for (MULTIBOOT.syms.addr[0..MULTIBOOT.syms.num]) |section| {
        const name = @intToPtr([*:0]const u8, section_names.sh_addr + section.sh_name);
        vga.format("{s}\n", .{name});
        if (name.len == ".symtab".len and std.mem.compare) {

        }
    } else return SymbolsError.NoSymbol;
    _ = symbol_section;
}
