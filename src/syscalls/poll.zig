const std = @import("std");
const scheduler = @import("../scheduler.zig");
const serial = @import("../serial.zig");
const errno = @import("errno.zig");
const fs = @import("../io/fs.zig");

const File = fs.File;
const SyscallError = errno.SyscallError;
const Event = scheduler.Event;

pub const Pollfd = packed struct {
    fd: i32,
    /// Requested events
    events: PollEvent,
    /// Returned events
    revents: PollEvent,
};

pub const PollEvent = packed struct {
    POLLIN: bool,
    POLLPRI: bool,
    POLLOUT: bool,
    POLLERR: bool,
    POLLHUP: bool,
    POLLNVAL: bool,
    pad: u10,
};

pub noinline fn poll(fds: usize, fdcnt: usize, timeout: u32) isize {
    var phy_ptr = scheduler.runningProcess.pd.virtToPhy(fds) orelse return -errno.EFAULT;
    var pollfds = @intToPtr([*]Pollfd, phy_ptr)[0..fdcnt];
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("poll called with fds={*}, timeout={}", .{ pollfds, timeout });
    return do_poll(pollfds, timeout) catch |err| return -errno.errorToErrno(err);
}

fn do_poll(fds: []Pollfd, timeout: u32) SyscallError!isize {
    while (true) {
        var ret: isize = 0;
        for (fds) |*pollfd| {
            const fd: usize = if (pollfd.fd >= 0) @intCast(usize, pollfd.fd) else continue;
            var file: *File = scheduler.runningProcess.fd[fd] orelse return error.BadFD;
            var status = file.dentry.inode.poll();
            var updated = false;
            pollfd.revents = std.mem.zeroes(PollEvent);
            if (pollfd.events.POLLIN and status.readable) {
                pollfd.revents.POLLIN = true;
                updated = true;
            }
            if (pollfd.events.POLLOUT and status.writable) {
                pollfd.revents.POLLOUT = true;
                updated = true;
            }
            if (updated) {
                ret += 1;
            }
        }
        if (ret != 0) {
            return ret;
        } else {
            if (timeout == 0) {
                return ret;
            } else {
                try pollWaitForEvents(fds);
            }
        }
    }
}

fn pollWaitForEvents(fds: []Pollfd) SyscallError!void {
    for (fds) |*pollfd| {
        const fd: usize = if (pollfd.fd >= 0) @intCast(usize, pollfd.fd) else continue;
        var file: *File = scheduler.runningProcess.fd[fd] orelse return error.BadFD;
        if (pollfd.events.POLLIN) {
            try scheduler.queueEvent(Event{ .IO_WRITE = file.dentry.inode }, scheduler.runningProcess);
        }
        if (pollfd.events.POLLOUT) {
            try scheduler.queueEvent(Event{ .IO_READ = file.dentry.inode }, scheduler.runningProcess);
        }
    }
    scheduler.runningProcess.status = .Sleeping;
    scheduler.canSwitch = true;
    asm volatile ("int $0x81");
    scheduler.canSwitch = false;
    for (fds) |*pollfd| {
        const fd: usize = if (pollfd.fd >= 0) @intCast(usize, pollfd.fd) else continue;
        var file: *File = scheduler.runningProcess.fd[fd] orelse return error.BadFD;
        if (pollfd.events.POLLIN) {
            scheduler.removeEvent(Event{ .IO_WRITE = file.dentry.inode }, scheduler.runningProcess);
        }
        if (pollfd.events.POLLOUT) {
            scheduler.removeEvent(Event{ .IO_READ = file.dentry.inode }, scheduler.runningProcess);
        }
    }
}
