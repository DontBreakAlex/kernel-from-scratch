const kernfs = @import("kernfs.zig");
const dirent = @import("dirent.zig");

const DirEnt = dirent.DirEnt;

var inode: *kernfs.Inode = undefined;

pub fn init(dev_dirent: *DirEnt) !void {
    inode = try kernfs.Inode.create(.{ .Directory = .{} });
    try dev_dirent.mount(.{ .kern = inode });
}

pub fn createTTY() !void {}
