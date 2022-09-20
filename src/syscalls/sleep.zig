const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");

pub noinline fn nanosleep(rqtp: usize, rmtp: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("nanosleep called with rqtp=0x{x}, rmtp=0x{x}", .{ rqtp, rmtp });
    return do_sleep();
}

fn do_sleep() isize {
    if (!scheduler.canSwitch)
        unreachable;
    scheduler.wantsToSwitch = true;
    return 0;
}
