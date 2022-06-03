const scheduler = @import("../scheduler.zig");
const std = @import("std");
const f = @import("fcntl.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const File = @import("../io/fs.zig").File;
const Mode = @import("../io/mode.zig").Mode;

pub noinline fn open(buff: usize, size: usize, flags: usize, raw_mode: u16) isize {
    var path = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    var dentry: *DirEnt = undefined;
    var result = scheduler.runningProcess.cwd.resolve(path, &dentry) catch return -1;
    if (result == .ParentExists) {
        if (flags & f.O_CREAT == 1 and flags & f.O_DIRECTORY == 0) {
            const name = path[std.mem.lastIndexOf(u8, path, "/") orelse return -1..path.len];
            const mode = std.mem.bytesToValue(Mode, std.mem.asBytes(&raw_mode));

            const child = try dentry.createChild(name, .Regular, mode);
            return child;
        } else {
            return -1;
        }
    }

    const fd = scheduler.runningProcess.getAvailableFd() catch return -1;
    var file: *File = switch (dentry.e_type) {
        .Directory => if (flags & f.O_DIRECTORY == 0) return -1 else File.create(dentry, @intCast(u8, flags)) catch return -1,
        .Regular => File.create(dentry, @intCast(u8, flags)) catch return -1,
        else => return -1,
    };
    scheduler.runningProcess.fd[fd] = file;
    return @intCast(isize, fd);
}
