const scheduler = @import("../scheduler.zig");
const serial = @import("../serial.zig");

pub noinline fn read(fd: usize, buff: usize, count: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("read called with fd={}", .{fd});
    return do_read(fd, buff, count) catch -1;
}

fn do_read(fd: usize, buff: usize, count: usize) !isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    if (scheduler.runningProcess.fd[fd]) |file| {
        var user_buf = try scheduler.runningProcess.pd.vBufferToPhy(count, buff);
        return @intCast(isize, try file.read(user_buf));
    }
    return -1;
}
