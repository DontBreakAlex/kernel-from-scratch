const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");

pub noinline fn getpid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getpid called", .{});
    return scheduler.runningProcess.pid;
}

pub noinline fn getppid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getppid called", .{});
    return scheduler.runningProcess.parent.?.pid;
}

pub noinline fn getuid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getuid called", .{});
    return scheduler.runningProcess.uid;
}

pub noinline fn getgid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getgid called", .{});
    return scheduler.runningProcess.gid;
}

pub noinline fn geteuid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("geteuid called", .{});
    return scheduler.runningProcess.euid;
}

pub noinline fn getegid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getegid called", .{});
    return scheduler.runningProcess.egid;
}

pub noinline fn getcwd(buff: usize, size: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getcwd called with buff=9x{x}, size={}", .{ buff, size });
    var user_buf = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    var cnt = scheduler.runningProcess.cwd.copyPath(user_buf) catch return -1;
    user_buf[cnt] = 0;
    return @intCast(isize, cnt) + 1;
}
