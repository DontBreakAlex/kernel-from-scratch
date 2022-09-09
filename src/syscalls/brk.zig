const serial = @import("../serial.zig");
const std = @import("std");
const paging = @import("../memory/paging.zig");

const s = @import("../scheduler.zig");

pub noinline fn brk(new_brk: usize) isize {
    serial.format("brk called with: {x}\n", .{ new_brk });
    serial.format("{x}\n", .{ s.runningProcess.brk });
    if (new_brk > s.runningProcess.brk)
        increaseBrk(new_brk) catch @panic("brk failure")
    else
        reduceBrk(new_brk) catch @panic("brk failure");
    s.runningProcess.brk = new_brk;
    return @intCast(isize, s.runningProcess.base_brk + new_brk);
    // return 0;
}

fn increaseBrk(new_brk: usize) !void {
    var first_page = std.mem.alignForward(s.runningProcess.base_brk + s.runningProcess.brk, paging.PAGE_SIZE);
    var last_page = std.mem.alignBackward(s.runningProcess.base_brk + new_brk, paging.PAGE_SIZE);
    while (first_page <= last_page) : (first_page += paging.PAGE_SIZE) {
        try s.runningProcess.pd.allocVirt(first_page, paging.WRITE | paging.USER);
    }
}

fn reduceBrk(new_brk: usize) !void {
    var first_page = std.mem.alignForward(s.runningProcess.base_brk + new_brk, paging.PAGE_SIZE);
    var last_page = std.mem.alignBackward(s.runningProcess.base_brk + s.runningProcess.brk, paging.PAGE_SIZE);
    while (first_page <= last_page) : (first_page += paging.PAGE_SIZE) {
        try s.runningProcess.pd.freeVirt(first_page);
    }
}