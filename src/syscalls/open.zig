const scheduler = @import("../scheduler.zig");
const std = @import("std");
const f = @import("../io/fcntl.zig");
const log = @import("../log.zig");
const serial = @import("../serial.zig");
const errno = @import("errno.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const File = @import("../io/fs.zig").File;
const Mode = @import("../io/mode.zig").Mode;

pub noinline fn open(buff: usize, flags: usize, raw_mode: u16) isize {
    var path = std.mem.span(@intToPtr([*:0]const u8, scheduler.runningProcess.pd.virtToPhy(buff) orelse return -1));
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("open called with path={s}, flags={o}, mode={}", .{ path, flags, raw_mode });
    return do_open(path, flags, raw_mode);
}
fn do_open(path: []const u8, flags: usize, raw_mode: u16) isize {
    var dentry: *DirEnt = switch (scheduler.runningProcess.cwd.resolveWithResult(path) catch return -1) {
        .Found => |d| d,
        .ParentExists => |d| blk: {
            const a = flags & f.O_CREAT;
            const b = flags & f.O_DIRECTORY;
            if (a == f.O_CREAT and b == 0) {
                const start = (std.mem.lastIndexOf(u8, path, "/") orelse return -1) + 1;
                const name = path[start..path.len];

                break :blk d.createChild(name, .Regular, Mode.fromU16(raw_mode)) catch return -1;
            } else {
                return -1;
            }
        },
        .NotFound => return -1,
    };

    const fd = scheduler.runningProcess.getAvailableFd() catch return -1;
    var file: *File = switch (dentry.e_type) {
        .Directory => if (flags & f.O_DIRECTORY == 0) return -1 else File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)) catch return -1,
        .Regular => File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)) catch return -1,
        .CharDev => File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)) catch return -1,
        else => return -1,
    };
    // log.format("{s}\n", .{ file.dentry.inode.ext.mode });
    scheduler.runningProcess.fd[fd] = file;
    return @intCast(isize, fd);
}
