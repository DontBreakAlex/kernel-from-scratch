const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const e = @import("errno.zig");

pub const ENOIOCTLCMD = 515;

pub noinline fn ioctl(fd: usize, cmd: usize, arg: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("ioctl called with fd=0x{x}, cmd=0x{x}, arg=0x{x}", .{ fd, cmd, arg });
    var file = scheduler.runningProcess.fd[fd] orelse return -e.EBADF;
    return file.dentry.inode.ioctl(cmd, arg);
}
