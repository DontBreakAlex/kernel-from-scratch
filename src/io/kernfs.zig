const mode = @import("mode.zig");
const std = @import("std");
const dirent = @import("dirent.zig");
const mem = @import("../memory/mem.zig");

const Type = mode.Type;
const Children = std.TailQueue(*Inode);
const InodeRef = dirent.InodeRef;
const Kind = union(enum) { Directory: Children, Symlink: InodeRef };

pub const Inode = struct {
    const Self = @This();

    refcount: usize,
    kind: Kind,

    /// Caller is responsible to call release() on the inode
    pub fn create(kind: Kind) !*Self {
        var node = try mem.allocator.create(Self);
        node.refcount = 1;
        node.kind = kind;
        return node;
    }

    pub fn createDir() !*Self {
        return Self.create(Kind{ .Directory = Children{} });
    }

    pub fn createSymlink(target: InodeRef) !*Self {
        return Self.create(Kind{ .Symlink = target });
    }

    pub fn link(self: *Self, child: *Self) !void {
        var node = try mem.allocator.create(Children.Node);
        node.data = child;
        self.kind.Directory.append(node);
    }
};
