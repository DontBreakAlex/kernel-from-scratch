const std = @import("std");

pub fn main() !void {
    try func();
}

pub fn func() !void {
    const stdout = std.io.getStdOut().writer();
    errdefer stdout.print("1\n", .{}) catch unreachable;
    errdefer stdout.print("2\n", .{}) catch unreachable;
    return error.Error;
}
