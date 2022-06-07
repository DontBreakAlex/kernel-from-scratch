const scheduler = @import("../scheduler.zig");
const std = @import("std");
const f = @import("../io/fcntl.zig");
const log = @import("../log.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const File = @import("../io/fs.zig").File;
const Mode = @import("../io/mode.zig").Mode;

pub noinline fn open(buff: usize, size: usize, flags: usize, raw_mode: u16) isize {
    var path = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    var dentry: *DirEnt = undefined;
    var result = scheduler.runningProcess.cwd.resolve(path, &dentry) catch return -1;
    if (result == .ParentExists) {
        if (flags & f.O_CREAT == f.O_CREAT and flags & f.O_DIRECTORY == 0) {
            const name = path[std.mem.lastIndexOf(u8, path, "/") orelse return -1..path.len];

            dentry = dentry.createChild(name, .Regular, Mode.fromU16(raw_mode)) catch return -1;
        } else {
            return -1;
        }
    }

    const fd = scheduler.runningProcess.getAvailableFd() catch return -1;
    var file: *File = switch (dentry.e_type) {
        .Directory => if (flags & f.O_DIRECTORY == 0) return -1 else File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)) catch return -1,
        .Regular => File.create(dentry, @truncate(u16, flags & f.O_ACCMODE)) catch return -1,
        else => return -1,
    };
    log.format("{s}\n", .{ file.dentry.inode.ext.mode });
    scheduler.runningProcess.fd[fd] = file;
    return @intCast(isize, fd);
}
