const dirent = @import("io/dirent.zig");
const pipefs = @import("io/pipefs.zig");

const DirEnt = dirent.DirEnt;

pub fn createPipe() !*DirEnt {
    var inode = try pipefs.Inode.create();
    defer inode.release();
    var dentry = DirEnt.create(.{ .pipe = inode }, null, &.{}, .CharDev);
    return dentry;
}
