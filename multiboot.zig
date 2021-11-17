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
    unused: u19,
};

pub const MultibootInfo = packed struct {
    flags: Flags,
};

pub var MULTIBOOT: *MultibootInfo = undefined;

export fn read_multiboot() callconv(.C) void {
    @compileError("{}", .{ @sizeOf(Flags) });
}
