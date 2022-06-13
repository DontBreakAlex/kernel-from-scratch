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
        const a = flags & f.O_CREAT;
        const b = flags & f.O_DIRECTORY;
        if (a == f.O_CREAT and b == 0) {
            const start = (std.mem.lastIndexOf(u8, path, "/") orelse return -1) + 1;
            const name = path[start..path.len];

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
    // log.format("{s}\n", .{ file.dentry.inode.ext.mode });
    scheduler.runningProcess.fd[fd] = file;
    return @intCast(isize, fd);
}
