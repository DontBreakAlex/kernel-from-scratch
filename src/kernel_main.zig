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
    const first_trace_addr = @returnAddress();
    const info = std.debug.openSelfDebugInfo(utl.allocator);
    var it = std.debug.StackIterator.init(first_trace_addr, null);
    while (it.next()) |return_address| {
        vga.format("{x:0>8}\n", .{ return_address });
    }
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
