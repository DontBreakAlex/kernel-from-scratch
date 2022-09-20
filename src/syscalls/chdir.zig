const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");

pub noinline fn chdir(buff: usize, size: usize) isize {
    var path = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("chdir called with path={s}", .{path});
    scheduler.runningProcess.cwd = scheduler.runningProcess.cwd.resolve(path) catch return -1;
    return 0;
}
