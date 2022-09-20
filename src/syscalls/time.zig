const t = @import("../time.zig");
const serial = @import("../serial.zig");

pub noinline fn time(ptr: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("time called with ptr=0x{x}", .{ptr});
    if (ptr != 0)
        return -1;
    return @intCast(isize, t.seconds_since_epoch);
}
