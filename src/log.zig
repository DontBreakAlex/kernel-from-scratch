const serial = @import("serial.zig");
const vga = @import("vga.zig");

pub fn format(comptime fmt: []const u8, args: anytype) void {
    serial.format(fmt, args);
    vga.format(fmt, args);
}
