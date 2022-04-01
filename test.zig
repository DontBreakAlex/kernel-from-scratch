const std = @import("std");

pub fn main() !void {
    var data = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' };
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}\n", .{ data[1..3] });
}