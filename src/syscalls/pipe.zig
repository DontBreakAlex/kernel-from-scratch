const f = @import("../io/fcntl.zig");
const scheduler = @import("../scheduler.zig");
const createPipe = @import("../pipe.zig").createPipe;
const fs = @import("../io/fs.zig");
const serial = @import("../serial.zig");

pub noinline fn pipe(us_fds: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("pipe called with fds=0x{x}", .{us_fds});
    return do_pipe(us_fds) catch return -1;
}
pub noinline fn do_pipe(us_fds: usize) !isize {
    const new_pipe = try createPipe();
    defer new_pipe.release();
    const ks_fds = try scheduler.runningProcess.pd.vPtrToPhy([2]usize, @intToPtr(*[2]usize, us_fds));
    const fd_out = try scheduler.runningProcess.getAvailableFd();
    scheduler.runningProcess.fd[fd_out] = try fs.File.create(new_pipe, f.O_RDONLY);
    errdefer scheduler.runningProcess.fd[fd_out] = null;
    errdefer scheduler.runningProcess.fd[fd_out].?.close();
    const fd_in = try scheduler.runningProcess.getAvailableFd();
    scheduler.runningProcess.fd[fd_in] = try fs.File.create(new_pipe, f.O_WRONLY);
    errdefer scheduler.runningProcess.fd[fd_in] = null;
    errdefer scheduler.runningProcess.fd[fd_in].?.close();
    ks_fds[0] = fd_out;
    ks_fds[1] = fd_in;
    return 0;
}
