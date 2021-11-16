const std = @import("std");
const idt = @import("idt.zig");
const vga = @import("vga.zig");
const pic = @import("pic.zig");
const kbr = @import("keyboard.zig");
const shl = @import("shell.zig");
const utl = @import("utils.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    vga.format("KERNEL PANIC: {s}\n", .{ msg });
    utl.boch_break();
    utl.halt();
    while (true) {}
}

export fn kernel_main() void {
    vga.init();
    idt.init();
    pic.init();
    kbr.init();
    vga.init();

    utl.enable_int();
    shl.run();
}
