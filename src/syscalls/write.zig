const scheduler = @import("../scheduler.zig");
const serial = @import("../serial.zig");

const IoVec = packed struct {
    iov_base: usize,
    iov_len: usize,
};

pub noinline fn write(fd: usize, buff: usize, count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    var user_buf = scheduler.runningProcess.pd.vBufferToPhy(count, buff) catch return -1;
    const ret = do_write(fd, user_buf) catch return -1;
    return @intCast(isize, ret);
}

pub noinline fn writev(fd: usize, iovec_ptr: usize, iovec_cnt: usize) isize {
    var ret: usize = 0;
    const phy_ptr = scheduler.runningProcess.pd.virtToPhy(iovec_ptr) orelse return -1;
    var vecs = @intToPtr([*]IoVec, phy_ptr)[0..iovec_cnt];
    for (vecs) |vec| {
        var buff = @intToPtr([*]u8, scheduler.runningProcess.pd.virtToPhy(vec.iov_base) orelse return -1)[0..vec.iov_len];
        serial.format("vec: {s}\n", .{buff});
        ret += do_write(fd, buff) catch return -1;
    }
    return @intCast(isize, ret);
}

fn do_write(fd: usize, buffer: []const u8) !usize {
    if (scheduler.runningProcess.fd[fd]) |file| {
        return file.write(buffer);
    }
    return error.NoFd;
}
