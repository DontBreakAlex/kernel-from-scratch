const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");

pub noinline fn getpid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getpid called", .{});
    return scheduler.runningProcess.pid;
}

pub noinline fn getuid() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getuid called", .{});
    return scheduler.runningProcess.owner_id;
}

pub noinline fn getcwd(buff: usize, size: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("getcwd called with buff=9x{x}, size={}", .{ buff, size });
    var user_buf = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    var cnt = scheduler.runningProcess.cwd.copyPath(user_buf) catch return -1;
    user_buf[cnt] = 0;
    return @intCast(isize, cnt) + 1;
}
