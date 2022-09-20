const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const process = @import("../process.zig");

const Child = process.Child;

pub noinline fn waitpid(pid: usize, stat_addr: usize, options: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("waitpid called with pid={}, stat_addr=0x{x}, options={}", .{ pid, stat_addr, options });
    return do_waitpid();
}

fn do_waitpid() isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    var child = scheduler.runningProcess.childrens.first;
    var prev: ?*Child = null;
    while (true) {
        scheduler.runningProcess.status = .Sleeping;
        scheduler.canSwitch = true;
        asm volatile ("int $0x81");
        scheduler.canSwitch = false;
        while (child) |c| {
            if (c.data.status == .Zombie) {
                const pid = c.data.pid;
                serial.format("Process {} found dead child with PID {}\n", .{ scheduler.runningProcess.pid, pid });
                if (prev) |p| {
                    _ = p.removeNext();
                } else {
                    _ = scheduler.runningProcess.childrens.popFirst();
                }
                c.data.deinit();
                return @intCast(isize, pid);
            }
            prev = c;
            child = c.next;
        }
    }
    return -1;
}

pub noinline fn sigwait() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("sigwait called", .{});
    return do_sigwait();
}

fn do_sigwait() isize {
    if (!scheduler.canSwitch)
        unreachable;
    scheduler.runningProcess.status = .Sleeping;
    scheduler.wantsToSwitch = true;
    return 0;
}
