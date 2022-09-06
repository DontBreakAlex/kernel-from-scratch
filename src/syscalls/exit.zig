const scheduler = @import("../scheduler.zig");

pub noinline fn exit(code: usize) isize {
    scheduler.canSwitch = false;
    scheduler.runningProcess.status = .Zombie;
    scheduler.runningProcess.state = .{ .ExitCode = code };
    if (scheduler.runningProcess.parent) |parent| {
        if (parent.status == .Sleeping) {
            parent.status = .Paused;
            scheduler.queue.writeItem(parent) catch @panic("Alloc failure in exit");
        }
    } else @panic("Init process exited");
    scheduler.canSwitch = true;
    scheduler.schedule(undefined, undefined, undefined);
    return 0;
}