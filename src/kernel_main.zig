extern fn boch_break() void;
const std = @import("std");
const idt = @import("idt.zig");
const vga = @import("vga.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    vga.putStr("KERNEL PANIC\n");
    boch_break();
    while (true) {}
}

export fn kernel_main() void {
    vga.init();
    idt.setup();

    // boch_break();
    vga.format("Hello from main {d}\n", .{ 4 });
    // vga.putStr("Hello from main\n");
}
