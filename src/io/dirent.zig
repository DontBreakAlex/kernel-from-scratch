const std = @import("std");
const ext = @import("ext2.zig");
const fs = @import("fs.zig");
const mem = @import("../memory/mem.zig");
const cache = @import("cache.zig");
const serial = @import("../serial.zig");

const MAX_NESTED = 256;
const Inode = ext.Inode;

pub const Childrens = std.TailQueue(DirEnt);
pub const Child = Childrens.Node;
pub const Type = enum {
    Unknown,
    Regular,
    Directory,
    CharDev,
    Block,
    FIFO,
    Socket,
    Symlink,

    pub fn fromTypeIndicator(indicator: u8) !Type {
        return switch (indicator) {
            0 => .Unknown,
            1 => .Regular,
            2 => .Directory,
            3 => .CharDev,
            4 => .Block,
            5 => .FIFO,
            6 => .Socket,
            7 => .Symlink,
            else => return error.WrongTypeIndicator,
        };
    }
};

pub const InodeRef = union(enum) {
    const Self = @This();

    ext: *ext.Inode,

    pub fn populateChildren(self: Self, dirent: *DirEnt) !void {
        switch (self) {
            .ext => try self.ext.populateChildren(dirent),
        }
    }

    pub fn compare(lhs: Self, rhs: Self) bool {
        if (@enumToInt(lhs) != @enumToInt(rhs))
            return false;
        return switch (lhs) {
            .ext => lhs.ext == rhs.ext,
        };
    }
};

pub const DirEnt = struct {
    inode: InodeRef,
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
        totallen = if (parents.len == 1) totallen + 1 else totallen + (parents.len - 1);
        if (dst.len < totallen)
            return error.BufferTooSmall;
        if (totallen == 1) {
            dst[0] = '/';
            return totallen;
        }
        var cursor: usize = 0;
        var first = parents.pop();
        std.mem.copy(u8, dst[cursor .. cursor + first.namelen], first.getName());
        cursor += first.namelen;
        while (parents.popOrNull()) |entry| {
            dst[cursor] = '/';
            cursor += 1;
            var tmp = dst[cursor .. cursor + entry.namelen];
            std.mem.copy(u8, tmp, entry.getName());
            cursor += entry.namelen;
        }
        return totallen;
    }

    const Iterator = std.mem.TokenIterator(u8);
    pub fn resolve(self: *DirEnt, path: []const u8) !*DirEnt {
        var cursor: *DirEnt = if (path[0] == '/') &fs.root_dirent else self;
        var iterator: Iterator = std.mem.tokenize(u8, path, "/");
        while (iterator.next()) |name| {
            var next = try cursor.findChildren(name);
            if (InodeRef.compare(next.inode, cursor.inode)) {} else if (cursor.parent != null and InodeRef.compare(next.inode, cursor.parent.?.inode)) {
                cursor = cursor.parent.?;
            } else {
                cursor = next;
            }
        }
        return cursor;
    }

    fn findChildren(self: *DirEnt, name: []const u8) !*DirEnt {
        if (self.e_type != .Directory)
            return error.NotADirectory;
        if (self.children == null)
            try self.inode.populateChildren(self);
        var it = self.children.?.first;
        while (it) |node| : (it = node.next) {
            if (std.mem.eql(u8, node.data.getName(), name))
                return &node.data;
        }
        return error.NotFound;
    }
};
