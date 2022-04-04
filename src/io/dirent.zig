const std = @import("std");
const ext = @import("ext2.zig");

const Inode = ext.Inode;

const Childrens = std.TailQueue(DirEnt);
pub const Type = enum { Dir, Block };
pub const DirEnt = struct {
    inode: *Inode,
    parent: ?*DirEnt,
    e_type: Type,
    /// If childrens is null for a directory, it means that it hasn't been read yet
    children: ?Childrens,
    namlen: usize,
    name: [256]u8,

    pub fn getName(self: *const Dirent) []u8 {
        return self.name[0..self.namelen];
    }
};
