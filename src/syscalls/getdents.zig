const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const proc = @import("../process.zig");
const dirent = @import("../io/dirent.zig");

const Dentry = dirent.Dentry;

pub noinline fn getdents(fd: usize, buff: usize, size: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getdents called with fd={}, buff=0x{x}", .{ fd, buff });
    if (fd >= proc.FD_COUNT) return -1;
    var ptr = @intToPtr([*]Dentry, scheduler.runningProcess.pd.virtToPhy(buff) orelse return -1);
    var cnt = size;
    var file = scheduler.runningProcess.fd[fd] orelse return -1;
    _ = file.getDents(ptr, &cnt) catch return -1;
    return @intCast(isize, cnt);
}
