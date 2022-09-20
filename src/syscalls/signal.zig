const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const proc = @import("../process.zig");

pub noinline fn signal(sig: usize, handler: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("signal called with sig={}, handler=0x{x}", .{ sig, handler });
    return @bitCast(isize, scheduler.runningProcess.setSigHanlder(@intToEnum(proc.Signal, @truncate(u8, sig)), handler));
}
