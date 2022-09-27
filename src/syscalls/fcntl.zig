const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const errno = @import("errno.zig");
const dup = @import("dup.zig");

const LINUX_BASE = 1024;

// zig fmt: off
const Command = enum(usize) {
    F_DUPFD = 0,
    F_GETFD = 1,
    F_SETFD = 2,
    F_GETFL = 3,
    F_SETFL = 4,
    F_GETLK = 5,
    F_SETLK = 6,
    F_SETLKW = 7,
    F_SETOWN = 8,
    F_GETOWN = 9,
    F_SETSIG = 10,
    F_GETSIG = 11,
    F_DUPFD_CLOEXEC = LINUX_BASE + 6,
    _
};

const FD_CLOEXEC = 1;

pub noinline fn fcntl(fd: usize, cmd: usize, arg: usize) isize {
    var command = @intToEnum(Command, cmd);
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("fnctl called with fd={}, cmd={}, arg={}", .{ fd, command, arg });
    return do_fcntl(fd, command, arg);
}

pub noinline fn fcntl64(fd: usize, cmd: usize, arg: usize) isize {
    var command = @intToEnum(Command, cmd);
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("fnctl64 called with fd={}, cmd={}, arg={}", .{ fd, command, arg });
    return do_fcntl(fd, command, arg);
}

fn do_fcntl(fd: usize, cmd: Command, arg: usize) isize {
    _ = arg;
    return switch (cmd) {
        .F_DUPFD_CLOEXEC => @intCast(isize, dup.dupfd(fd) catch |err| return -errno.errorToErrno(err)),
        else => -errno.EINVAL,
    };
}
