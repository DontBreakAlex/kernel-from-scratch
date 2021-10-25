extern fn boch_break() void;
extern fn enable_int() void;
const std = @import("std");
const idt = @import("idt.zig");
const vga = @import("vga.zig");
const pic = @import("pic.zig");
const kbr = @import("keyboard.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    vga.putStr("KERNEL PANIC\n");
    boch_break();
    while (true) {}
}

export fn kernel_main() void {
    vga.init();
    idt.init();
    pic.init();
    kbr.init();

    vga.format("Hello from main\n", .{});
    enable_int();
}
