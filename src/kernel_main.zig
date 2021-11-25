const std = @import("std");
const idt = @import("idt.zig");
const vga = @import("vga.zig");
const pic = @import("pic.zig");
const kbr = @import("keyboard.zig");
const shl = @import("shell.zig");
const utl = @import("utils.zig");
const mlb = @import("multiboot.zig");
const mem = @import("memory.zig");

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
    mlb.loadSymbols() catch {};
    idt.init();
    pic.init();
    kbr.init();
    mem.init(mlb.MULTIBOOT.mem_upper);

    utl.enable_int();
    const a = mem.allocator.allocAdvanced(u8, 2, 4094, .exact) catch @panic("AllocFailed");
    for (a) |*i| {
        i.* = 'a';
    }
    const b = mem.allocator.alloc(u8, 4096) catch @panic("AllocFailed");
    for (b) |*i| {
        i.* = 'b';
    }
    std.debug.assert(std.mem.allEqual(u8, a, 'a'));
    std.debug.assert(std.mem.allEqual(u8, b, 'b'));
    shl.run();
}
