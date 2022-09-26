const serial = @import("../serial.zig");
const std = @import("std");
const paging = @import("../memory/paging.zig");

const s = @import("../scheduler.zig");

pub noinline fn brk(new_brk: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("brk called with: 0x{x}", .{new_brk});
    if (new_brk == 0) {
        return @intCast(isize, s.runningProcess.brk);
    }
    if (new_brk > s.runningProcess.brk)
        increaseBrk(new_brk) catch @panic("brk failure")
    else
        reduceBrk(new_brk) catch @panic("brk failure");
    s.runningProcess.brk = new_brk;
    return @intCast(isize, new_brk);
}

fn increaseBrk(new_brk: usize) !void {
    var first_page = std.mem.alignForward(s.runningProcess.brk, paging.PAGE_SIZE);
    var last_page = std.mem.alignForward(new_brk, paging.PAGE_SIZE);
    // serial.format("0x{x:0>8}-0x{x:0>8}\n", .{ first_page, last_page });
    while (first_page < last_page) : (first_page += paging.PAGE_SIZE) {
        try s.runningProcess.pd.allocVirt(first_page, paging.WRITE | paging.USER);
    }
}

fn reduceBrk(new_brk: usize) !void {
    var first_page = std.mem.alignForward(new_brk, paging.PAGE_SIZE);
    var last_page = std.mem.alignForward(s.runningProcess.brk, paging.PAGE_SIZE);
    while (first_page < last_page) : (first_page += paging.PAGE_SIZE) {
        try s.runningProcess.pd.freeVirt(first_page);
    }
}
