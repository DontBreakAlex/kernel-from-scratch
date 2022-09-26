const mode = @import("mode.zig");
const std = @import("std");
const dirent = @import("dirent.zig");
const mem = @import("../memory/mem.zig");
const inoderef = @import("inoderef.zig");

const Type = mode.Type;
const Children = std.StringHashMapUnmanaged(*Inode);
const InodeRef = dirent.InodeRef;
const Kind = union(enum) { Directory: Children, Symlink: InodeRef, Device: Fops };
const Status = inoderef.Status;

pub const Fops = struct {
    write: fn (buff: []const u8) usize,
    rawWrite: fn (buff: []const u8) usize,
    read: fn (buff: []u8) usize,
    rawRead: fn (buff: []u8) usize,
    ioctl: fn (cmd: usize, arg: usize) isize,
    poll: fn () Status,
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
        try self.kind.Directory.put(mem.allocator, name, child);
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
        _ = ptr;
        _ = cnt;
        _ = offset;
        _ = self;
        unreachable;
        // if (offset >= self.kind.Directory.size) {
        //     cnt.* = 0;
        //     return 0;
        // }
        // var cursor = self.kind.Directory.first;
        // var dst = ptr[0..cnt.*];
        // var i: usize = 0;
        // while (i < offset and cursor != null) : (i += 1)
        //     cursor = cursor.?.next;
        // i = 0;
        // while (cursor) |entry| {
        //     if (i >= dst.len)
        //         break;
        //     dst[i].inode = @truncate(u32, @ptrToInt(entry.data.inode));
        //     dst[i].namelen = entry.data.namelen;
        //     std.mem.copy(u8, &dst[i].name, entry.data.name[0..entry.data.namelen]);
        //     i += 1;
        //     cursor = cursor.?.next;
        // }
        // cnt.* = i;
        // return i;
    }

    pub fn getId(self: *const Self) u32 {
        return @ptrToInt(self);
    }

    pub fn ioctl(self: *const Self, cmd: usize, arg: usize) isize {
        const i = @import("../syscalls/ioctl.zig");
        return switch (self.kind) {
            .Directory => -i.ENOIOCTLCMD,
            .Symlink => -i.ENOIOCTLCMD,
            .Device => |fops| fops.ioctl(cmd, arg),
        };
    }

    pub fn poll(self: *const Self) Status {
        return switch (self.kind) {
            .Directory => .{ .readable = true, .writable = true },
            .Symlink => .{ .readable = true, .writable = true },
            .Device => |fops| fops.poll(),
        };
    }

    pub fn lookupChild(self: *const Self, name: []const u8, indicator: *u8) !?InodeRef {
        switch (self.kind) {
            .Directory => {
                var child = self.kind.Directory.get(name) orelse return null;
                indicator.* = switch (child.kind) {
                    else => 0,
                    .Directory => 2,
                    .Device => 3,
                };
                return InodeRef{ .kern = child };
            },
            else => return null,
        }
    }
};
