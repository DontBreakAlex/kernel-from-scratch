const serial = @import("../serial.zig");

pub noinline fn sigaction(signum: usize, action: usize, oldaction: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("sigaction called with signum={}, action=0x{x}, olaction=0x{x}", .{ signum, action, oldaction });
    return 0;
}
