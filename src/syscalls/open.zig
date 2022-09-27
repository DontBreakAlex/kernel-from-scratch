const scheduler = @import("../scheduler.zig");
const std = @import("std");
const f = @import("../io/fcntl.zig");
const log = @import("../log.zig");
const serial = @import("../serial.zig");
const errno = @import("errno.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const File = @import("../io/fs.zig").File;
const Mode = @import("../io/mode.zig").Mode;
const SyscallError = errno.SyscallError;

pub noinline fn open(buff: usize, flags: usize, raw_mode: u16) isize {
    var path = std.mem.span(@intToPtr([*:0]const u8, scheduler.runningProcess.pd.virtToPhy(buff) orelse return -errno.EFAULT));
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("open called with path={s}, flags={o}, mode={}", .{ path, flags, raw_mode });
    return do_open(path, flags, raw_mode) catch |err| return -errno.errorToErrno(err);
}
fn do_open(path: []const u8, flags: usize, raw_mode: u16) !isize {
    var dentry: *DirEnt = switch (try scheduler.runningProcess.cwd.resolveWithResult(path)) {
        .Found => |d| d,
        .ParentExists => |d| blk: {
            const a = flags & f.O_CREAT;
            const b = flags & f.O_DIRECTORY;
            if (a == f.O_CREAT and b == 0) {
                const start = (std.mem.lastIndexOf(u8, path, "/") orelse return SyscallError.BadAddress) + 1;
                const name = path[start..path.len];

                break :blk d.createChild(name, .Regular, Mode.fromU16(raw_mode)) catch return SyscallError.IOError;
            } else {
                return SyscallError.NoSuchFile;
            }
        },
        .NotFound => return SyscallError.NoSuchFile,
    };

    const fd = try scheduler.runningProcess.getAvailableFd();
    var file: *File = switch (dentry.e_type) {
        .Directory => if (flags & f.O_DIRECTORY == 0)
            return SyscallError.IsADirectory
        else
            try File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)),
        .Regular => try File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)),
        .CharDev => try File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)),
        else => return SyscallError.IOError,
    };
    // log.format("{s}\n", .{ file.dentry.inode.ext.mode });
    scheduler.runningProcess.fd[fd] = file;
    return @intCast(isize, fd);
}
