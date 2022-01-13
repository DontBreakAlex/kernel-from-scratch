const utils = @import("utils.zig");
const std = @import("std");
const COM1 = 0x3F8;

pub fn init() !void {
    try initPort(COM1);
    format("Serial initialized\n", .{});
}

fn initPort(port: u16) !void {
    // Disable serial interrupts
    utils.out(port + 1, @as(u8, 0x00));
    // Set DLAB
    utils.out(port + 3, @as(u8, 0x80));
    // Set divisor lo byte
    utils.out(port + 0, @as(u8, 0x03));
    // Set divisor hi byte
    utils.out(port + 1, @as(u8, 0x00));
    // Set Line Control Register (8N1)
    utils.out(port + 3, @as(u8, 0x03));
    // Enable FIFO
    utils.out(port + 2, @as(u8, 0xC7));
    // IRQs
    utils.out(port + 4, @as(u8, 0x0B));
    // Enable loopback mode
    utils.out(port + 4, @as(u8, 0x1E));

    utils.out(port + 0, @as(u8, 0x5D));
    if (utils.in(u8, port) != 0x5D) {
        return error.PortInitFailed;
    }

    utils.out(port + 4, @as(u8, 0x0F));
}

fn isReady(port: u16) bool {
    return utils.in(u8, port + 5) & 0x20 == 0x20;
}

pub fn write(port: u16, data: []const u8) void {
    for (data) |byte| {
        while (isReady(port) == false) {}
        utils.out(port, byte);
    }
}

const SerialError = error{};
fn writeCallBack(_: void, data: []const u8) SerialError!usize {
    write(COM1, data);
    return data.len;
}

pub const Writer = std.io.Writer(void, SerialError, writeCallBack);

pub fn format(comptime fmt: []const u8, args: anytype) void {
    std.fmt.format(Writer{ .context = {} }, fmt, args) catch {};
}
