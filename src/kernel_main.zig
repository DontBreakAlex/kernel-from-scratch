const std = @import("std");
const idt = @import("idt.zig");
const vga = @import("vga.zig");
const pic = @import("pic.zig");
const pit = @import("pit.zig");
const kbr = @import("keyboard.zig");
const shl = @import("shell.zig");
const utl = @import("utils.zig");
const mlb = @import("multiboot.zig");
const mem = @import("memory/mem.zig");
const sch = @import("scheduler.zig");
const sys = @import("syscalls.zig");
const srl = @import("serial.zig");

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    vga.format("KERNEL PANIC: {s}\n", .{msg});
    utl.printTrace();
    utl.boch_break();
    utl.halt();
    while (true) {}
}

export fn kernel_main() void {
    vga.init();
    srl.init() catch vga.putStr("Failed to init serial\n");
    idt.init();
    pic.init();
    // pit.init();
    mem.init(mlb.MULTIBOOT.mem_upper);
    // mlb.loadSymbols() catch {};
    kbr.init();
    sys.init();

    utl.enable_int();
    sch.startProcess(useless) catch {};
    // shl.run();
}

pub fn useless() void {
    while (true) {
        asm volatile (
            \\mov $57, %%eax
            \\int $0x80
            ::: "eax");
        const syscall_ret = asm volatile (
            \\mov $39, %%eax
            \\int $0x80
            : [ret] "={eax}" (-> usize),
            :
            : "eax"
        );
        vga.putPtr(syscall_ret);
        asm volatile (
            \\mov $162, %%eax
            \\int $0x80
            ::: "eax");
        asm volatile ("hlt");
    }
}
