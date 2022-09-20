const scheduler = @import("../scheduler.zig");
const serial = @import("../serial.zig");

pub noinline fn close(fd: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("close called with fd={}", .{fd});
    if (scheduler.runningProcess.fd[fd]) |file| {
        file.close();
        return 0;
    }
    return -1;
}
