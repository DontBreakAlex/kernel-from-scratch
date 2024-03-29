const std = @import("std");
const ext = @import("ext2.zig");
const pipe = @import("pipefs.zig");
const fs = @import("fs.zig");
const mem = @import("../memory/mem.zig");
const cache = @import("cache.zig");
const serial = @import("../serial.zig");
const kernfs = @import("./kernfs.zig");
const log = @import("../log.zig");
const errno = @import("../syscalls/errno.zig");

const MAX_NESTED = 256;
const Inode = ext.Inode;
const SyscallError = errno.SyscallError;

pub const Type = @import("mode.zig").Type;
const Mode = @import("mode.zig").Mode;

pub const Dentry = packed struct {
    inode: u32,
    namelen: usize,
    name: [256]u8,
};

pub const InodeRef = @import("inoderef.zig").InodeRef;

pub const DirEnt = struct {
    const Self = @This();

    refcount: usize,
    inode: InodeRef,
    parent: ?*Self,
    e_type: Type,
    namelen: usize,
    name: [256]u8,
    mnt: ?InodeRef, // Backup of this dirent's inode before mount
    unused: cache.UnusedNode,

    /// Takes ownership of the inode
    /// Acquires parent ownership
    pub fn create(inode: InodeRef, parent: ?*Self, name: []const u8, e_type: Type) !*Self {
        var self = try mem.allocator.create(Self);
        if (parent) |p| {
            p.acquire();
            errdefer p.release();
            try cache.dirents.put(.{ .parent = p, .name = name }, self);
        }
        self.* = .{
            .refcount = 1,
            .inode = inode,
            .parent = parent,
            .e_type = e_type,
            .namelen = name.len,
            .name = undefined,
            .mnt = null,
            .unused = undefined,
        };
        std.mem.copy(u8, &self.name, name);
        return self;
    }

    pub fn acquire(self: *Self) void {
        if (self.refcount == 0) {
            cache.unusedDirents.remove(&self.unused);
        }
        self.refcount += 1;
    }

    pub fn release(self: *Self) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            cache.unusedDirents.append(&self.unused);
        }
    }

    pub fn delete(self: *Self) void {
        self.inode.release();
        if (self.parent)
            self.parent.release();
        mem.allocator.destroy(self);
    }

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
    const ResolveResult = union(enum) {
        NotFound,
        Found: *DirEnt,
        ParentExists: *DirEnt,
    };

    pub fn resolveWithResult(self: *DirEnt, path: []const u8) SyscallError!ResolveResult {
        var cursor: *DirEnt = if (path[0] == '/') &fs.root_dirent else self;
        var iterator: Iterator = std.mem.tokenize(u8, path, "/");
        while (iterator.next()) |name| {
            if (cursor.findChildren(name)) |next| {
                if (InodeRef.compare(next.inode, cursor.inode)) {
                    // We are accessing `.`, do nothing
                } else if (cursor.parent != null and InodeRef.compare(next.inode, cursor.parent.?.inode)) {
                    cursor = cursor.parent.?; // This is `..`
                } else {
                    cursor = next;
                }
            } else |err| {
                if (err == error.NoSuchFile) {
                    if (iterator.next() == null) {
                        return ResolveResult{ .ParentExists = cursor };
                    }
                }
                return err;
            }
        }
        return ResolveResult{ .Found = cursor };
    }

    pub fn resolve(self: *DirEnt, path: []const u8) errno.SyscallError!*DirEnt {
        return switch (try self.resolveWithResult(path)) {
            .Found => |d| d,
            else => return error.NoSuchFile,
        };
    }

    pub fn findChildren(self: *DirEnt, name: []const u8) !*DirEnt {
        if (self.e_type != .Directory)
            return error.NotADirectory;
        if (cache.dirents.get(.{ .parent = self, .name = name })) |child| {
            return child;
        }
        var indicator: u8 = undefined;
        if (try self.inode.lookupChild(name, &indicator)) |inode| {
            return DirEnt.create(inode, self, name, try Type.fromTypeIndicator(indicator));
        }
        return error.NoSuchFile;
    }

    pub fn createChild(self: *Self, name: []const u8, e_type: Type, mode: Mode) !*DirEnt {
        if (self.e_type != .Directory)
            return error.NotADirectory;
        var inode = try self.inode.createChild(name, e_type, mode);
        var dirent = try DirEnt.create(inode, self, name, e_type);
        return dirent;
    }

    /// Takes ownership of to_mount
    pub fn mount(self: *Self, to_mount: InodeRef) !void {
        if (self.e_type != .Directory)
            return error.NotADirectory;
        // std.debug.assert(to_mount.e_type == .Directory);
        if (self.mnt != null)
            return error.AlreadyMounted;
        self.mnt = self.inode;
        self.inode = to_mount;
        // log.format("Mounted {s} on {*}\n", .{ to_mount, self });
    }

    pub fn umount(self: *Self) !void {
        if (self.e_type != .Directory)
            return error.NotADirectory;
        if (self.mnt) |mnt| {
            self.inode.release();
            self.inode = mnt;
            self.mnt = null;
        } else {
            return error.NotMounted;
        }
    }
};
