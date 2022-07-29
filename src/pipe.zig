const dirent = @import("io/dirent.zig");
const pipefs = @import("io/pipefs.zig");

const DirEnt = dirent.DirEnt;

pub fn createPipe() !*DirEnt {
    var inode = try pipefs.Inode.create();
    var dentry = DirEnt.create(.{ .pipe = inode }, null, &.{}, .CharDev);
    return dentry;
}
