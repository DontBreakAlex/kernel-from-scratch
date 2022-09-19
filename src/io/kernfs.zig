const mode = @import("mode.zig");
const std = @import("std");
const dirent = @import("dirent.zig");
const mem = @import("../memory/mem.zig");

const Type = mode.Type;
const Child = struct { // This needs to be a true dirent
    inode: *Inode,
    namelen: u8,
    name: [251]u8,
};
const Children = std.TailQueue(Child);
const InodeRef = dirent.InodeRef;
const Kind = union(enum) { Directory: Children, Symlink: InodeRef, Device: Fops };
const Fops = struct {
    write: fn (buff: []const u8) usize,
    rawWrite: fn (buff: []const u8) usize,
    read: fn (buff: []u8) usize,
    rawRead: fn (buff: []u8) usize,
};

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

    pub fn createChild(self: *Self, child: *Self, name: []const u8) !void {
        var node = try mem.allocator.create(Children.Node);
        node.data.inode = child;
        node.data.namelen = @intCast(u8, name.len);
        std.mem.copy(u8, &node.data.name, name);
        self.kind.Directory.append(node);
    }

    pub fn write(self: *Self, buff: []const u8) usize {
        return self.kind.Device.write(buff);
    }

    pub fn rawWrite(self: *Self, buff: []const u8) usize {
        return self.kind.Device.rawWrite(buff);
    }

    pub fn read(self: *Self, buff: []u8) usize {
        return self.kind.Device.read(buff);
    }

    pub fn rawRead(self: *Self, buff: []u8) usize {
        return self.kind.Device.rawRead(buff);
    }

    pub fn acquire(self: *Self) void {
        self.refcount += 1;
    }

    pub fn release(self: *Self) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            @panic("Released kernfs inode ?!");
        }
    }

    const Dentry = dirent.Dentry;
    pub fn getDents(self: *const Self, ptr: [*]Dentry, cnt: *usize, offset: usize) !usize {
        if (offset >= self.kind.Directory.len) {
            cnt.* = 0;
            return 0;
        }
        var cursor = self.kind.Directory.first;
        var dst = ptr[0..cnt.*];
        var i: usize = 0;
        while (i < offset and cursor != null) : (i += 1)
            cursor = cursor.?.next;
        i = 0;
        while (cursor) |entry| {
            if (i >= dst.len)
                break;
            dst[i].inode = @truncate(u32, @ptrToInt(entry.data.inode));
            dst[i].namelen = entry.data.namelen;
            std.mem.copy(u8, &dst[i].name, entry.data.name[0..entry.data.namelen]);
            i += 1;
            cursor = cursor.?.next;
        }
        cnt.* = i;
        return i;
    }

    pub fn getId(self: *const Self) u32 {
        return @ptrToInt(self);
    }
};
