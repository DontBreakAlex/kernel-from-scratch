const std = @import("std");
const ext = @import("ext2.zig");
const fs = @import("fs.zig");

const MAX_NESTED = 256;
const Inode = ext.Inode;

const Childrens = std.TailQueue(DirEnt);
const Child = Childrens.Node;
pub const Type = enum { Dir, Block };
pub const DirEnt = struct {
    inode: *Inode,
    parent: ?*DirEnt,
    e_type: Type,
    /// If childrens is null for a directory, it means that it hasn't been read yet
    children: ?Childrens,
    namelen: usize,
    name: [256]u8,

    pub fn getName(self: *const DirEnt) []const u8 {
        return self.name[0..self.namelen];
    }

    const Parents = std.BoundedArray(*const DirEnt, MAX_NESTED);
    pub fn copyPath(self: *const DirEnt, dst: []u8) !usize {
        var parents: Parents = Parents.init(0) catch unreachable;
        var current: ?*const DirEnt = self;
        var totallen: usize = 0;
        while (current) |c| {
            try parents.append(c);
            totallen += c.namelen;
            current = c.parent;
        }
        if (dst.len < totallen)
            return error.BufferTooSmall;
        var cursor: usize = 0;
        while (parents.popOrNull()) |entry| {
            std.mem.copy(u8, dst[cursor..entry.namelen], entry.getName());
            cursor += entry.namelen;
        }
        return totallen;
    }

    // const Iterator = *std.mem.TokenIterator(u8);
    // pub fn resolve(self: *DirEnt, path: []u8) *DirEnt {
    //     var cursor: *DirEnt = if (path[0] == '/') fs.root_dirent else self;
    //     var iterator: Iterator = std.mem.tokenize(u8, path, "/");

    // }

    // fn findChildren(self: *DirEnt, name: []u8) !*DirEnt {
    //     if (self.e_type != .Dir)
    //         return error.NotADirectory;
    //     if (self.children == null)
    //         try self.readChildren();
    // }

    // fn readChildren() !void {

    // }
};
