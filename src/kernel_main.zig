const std = @import("std");
const idt = @import("idt.zig");
const vga = @import("vga.zig");
const pic = @import("pic.zig");
const kbr = @import("keyboard.zig");
const shl = @import("shell.zig");
const utl = @import("utils.zig");
const mlb = @import("multiboot.zig");

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    vga.format("KERNEL PANIC: {s}\n", .{msg});
    const first_trace_addr = @returnAddress();
    var it = std.debug.StackIterator.init(first_trace_addr, null);
    while (it.next()) |return_address| {
        vga.format("{x:0>8}\n", .{return_address});
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

    utl.enable_int();
    // const first_section = mlb.MULTIBOOT.syms.addr[1];
    // const string_table = mlb.MULTIBOOT.syms.addr[mlb.MULTIBOOT.syms.shndx];
    // const sec_name: CStr = @intToPtr([*:0]const u8, string_table.sh_addr + first_section.sh_name);
    // vga.format("{s}\n", .{sec_name});
    mlb.loadSymbols() catch {};
    // shl.run();
}
