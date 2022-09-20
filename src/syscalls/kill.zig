const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const proc = @import("../process.zig");

pub noinline fn kill(pid: usize, sig: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("kill called", .{});
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    const process = scheduler.processes.get(@intCast(u16, pid)) orelse return -1;
    process.queueSignal(@intToEnum(proc.Signal, sig)) catch return -1;
    return 0;
}
