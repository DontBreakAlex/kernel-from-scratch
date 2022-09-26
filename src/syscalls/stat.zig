const std = @import("std");
const time = @import("../time.zig");
const s = @import("../scheduler.zig");
const serial = @import("../serial.zig");
const errno = @import("errno.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const Timespec = time.Timespec;
const SyscallError = errno.SyscallError;

pub const Stat = extern struct {
    st_dev: u32,
    st_ino: u32,
    st_mode: u16,
    st_nlink: u16,
    st_uid: u16,
    st_gid: u16,
    st_rdev: u16,
    __pad2: u16,
    st_size: u32,
    st_blksize: u32,
    st_blocks: u32,
    st_atim: Timespec,
    st_mtim: Timespec,
    st_ctim: Timespec,
    __unused4: u32,
    __unused5: u32,
};
pub const Stat64 = extern struct {
    st_dev: u64,
    __pad0: [4]u8,
    __st_ino: u32,
    st_mode: u32,
    st_nlink: u32,
    st_uid: u32,
    st_gid: u32,
    st_rdev: u16,
    __pad3: [10]u8,
    st_size: i64,
    st_blksize: u32,
    st_blocks: u32,
    __pad4: u32,
    st_atim: Timespec,
    st_mtim: Timespec,
    st_ctim: Timespec,
    st_ino: u64,
};

pub noinline fn stat64(ptr: usize, statbuf: usize) isize {
    var path = std.mem.span(@intToPtr([*:0]const u8, s.runningProcess.pd.virtToPhy(ptr) orelse return -errno.EFAULT));
    var buff = @intToPtr(*Stat64, s.runningProcess.pd.virtToPhy(statbuf) orelse return -errno.EFAULT);
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("stat64 called with path={s}, statbuf=0x{x}", .{ path, statbuf });
    var dentry: *DirEnt = s.runningProcess.cwd.resolve(path) catch |err| return -errno.errorToErrno(err);
    do_stat64(dentry, buff) catch |err| return -errno.errorToErrno(err);
    return 0;
}

pub noinline fn fstat(fd: usize, statbuf: usize) isize {
    var buff = @intToPtr(*Stat, s.runningProcess.pd.virtToPhy(statbuf) orelse return -1);
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("fstat called with fd={}, statbuf=0x{x}", .{ fd, statbuf });
    var dentry: *DirEnt = (s.runningProcess.fd[fd] orelse return -1).dentry;
    do_stat(dentry, buff) catch return -1;
    return 0;
}

fn do_stat64(dentry: *DirEnt, statbuf: *Stat64) !void {
    statbuf.st_dev = dentry.inode.getDevId();
    statbuf.st_ino = dentry.inode.getId();
    statbuf.__st_ino = dentry.inode.getId();
    statbuf.st_mode = dentry.inode.getMode();
    statbuf.st_nlink = dentry.inode.getLinkCount();
    statbuf.st_uid = dentry.inode.getUid();
    statbuf.st_gid = dentry.inode.getGid();
    statbuf.st_rdev = 0;
    statbuf.st_size = dentry.inode.getSize();
    statbuf.st_blksize = dentry.inode.getBlkSize();
    statbuf.st_blocks = @intCast(u32, @divTrunc(statbuf.st_size + 511, 512));
    statbuf.st_atim = .{ .tv_sec = 0, .tv_nsec = 0 };
    statbuf.st_mtim = .{ .tv_sec = 0, .tv_nsec = 0 };
    statbuf.st_ctim = .{ .tv_sec = 0, .tv_nsec = 0 };

    // serial.format("{s}\n", .{statbuf.*});
}

fn do_stat(dentry: *DirEnt, statbuf: *Stat) !void {
    statbuf.st_dev = dentry.inode.getDevId();
    statbuf.st_ino = dentry.inode.getId();
    statbuf.st_mode = dentry.inode.getMode();
    statbuf.st_nlink = dentry.inode.getLinkCount();
    statbuf.st_uid = dentry.inode.getUid();
    statbuf.st_gid = dentry.inode.getGid();
    statbuf.st_rdev = 0;
    statbuf.st_size = dentry.inode.getSize();
    statbuf.st_blksize = dentry.inode.getBlkSize();
    statbuf.st_blocks = @intCast(u32, @divTrunc(statbuf.st_size + 511, 512));
    statbuf.st_atim = .{ .tv_sec = 0, .tv_nsec = 0 };
    statbuf.st_mtim = .{ .tv_sec = 0, .tv_nsec = 0 };
    statbuf.st_ctim = .{ .tv_sec = 0, .tv_nsec = 0 };
}
