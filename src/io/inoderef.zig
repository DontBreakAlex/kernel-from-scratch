const ext = @import("ext2.zig");
const pipe = @import("pipefs.zig");
const kernfs = @import("./kernfs.zig");
const errno = @import("../syscalls/errno.zig");

const Type = @import("mode.zig").Type;
const Dentry = @import("dirent.zig").Dentry;
const Mode = @import("mode.zig").Mode;
const SyscallError = errno.SyscallError;

pub const Status = packed struct {
    readable: bool,
    writable: bool,
};

pub const InodeRef = union(enum) {
    const Self = @This();

    ext: *ext.Inode,
    pipe: *pipe.Inode,
    kern: *kernfs.Inode,

    pub fn lookupChild(self: Self, name: []const u8, indicator: *u8) !?InodeRef {
        return switch (self) {
            .ext => try self.ext.lookupChild(name, indicator),
            .pipe => null,
            .kern => self.kern.lookupChild(name, indicator),
        };
    }

    pub fn compare(lhs: Self, rhs: Self) bool {
        if (@enumToInt(lhs) != @enumToInt(rhs))
            return false;
        return switch (lhs) {
            .ext => lhs.ext == rhs.ext,
            .pipe => lhs.pipe == rhs.pipe,
            .kern => lhs.kern == rhs.kern,
        };
    }

    pub fn currentSize(self: *const Self) usize {
        return switch (self) {
            .ext => self.ext.currentSize(),
            .pipe => self.pipe.currentSize(),
            .kern => unreachable,
        };
    }

    pub fn hasOffset(self: Self) bool {
        return switch (self) {
            .ext => true,
            .pipe => false,
            .kern => false,
        };
    }

    pub fn read(self: Self, buff: []u8, offset: usize) SyscallError!usize {
        return try switch (self) {
            .ext => self.ext.read(buff, offset),
            .pipe => self.pipe.read(buff),
            .kern => self.kern.read(buff),
        };
    }

    pub fn rawRead(self: Self, buff: []u8, offset: usize) !usize {
        _ = offset;
        return switch (self) {
            .ext => unreachable,
            .pipe => try self.pipe.rawRead(buff),
            .kern => self.kern.rawRead(buff),
        };
    }

    pub fn write(self: Self, buff: []const u8, offset: usize) !usize {
        _ = offset;
        return switch (self) {
            .ext => try self.ext.write(buff, offset),
            .pipe => try self.pipe.write(buff),
            .kern => self.kern.write(buff),
        };
    }

    pub fn rawWrite(self: Self, buff: []const u8, offset: usize) !usize {
        _ = offset;
        return switch (self) {
            .ext => unreachable,
            .pipe => try self.pipe.rawWrite(buff),
            .kern => self.kern.rawWrite(buff),
        };
    }

    pub fn poll(self: Self) Status {
        return switch (self) {
            .ext => .{ .readable = true, .writable = true },
            .pipe => .{
                .readable = self.pipe.buffer.readableLength() != 0,
                .writable = self.pipe.buffer.writableLength() != 0,
            },
            .kern => self.kern.poll(),
        };
    }

    pub fn getDents(self: Self, ptr: [*]Dentry, cnt: *usize, offset: usize) !usize {
        return switch (self) {
            .ext => try self.ext.getDents(ptr, cnt, offset),
            .pipe => unreachable,
            .kern => try self.kern.getDents(ptr, cnt, offset),
        };
    }

    pub fn acquire(self: Self) void {
        switch (self) {
            .ext => self.ext.acquire(),
            .pipe => self.pipe.acquire(),
            .kern => self.kern.acquire(),
        }
    }

    pub fn release(self: Self) void {
        switch (self) {
            .ext => self.ext.release(),
            .pipe => self.pipe.release(),
            .kern => self.kern.release(),
        }
    }

    pub fn createChild(self: Self, name: []const u8, e_type: Type, mode: Mode) !InodeRef {
        return switch (self) {
            .ext => InodeRef{ .ext = try self.ext.createChild(name, e_type, mode) },
            .pipe => unreachable,
            .kern => unreachable,
        };
    }

    pub fn getDevId(self: Self) usize {
        return switch (self) {
            .ext => self.ext.getDevId(),
            .pipe => 1,
            .kern => 2,
        };
    }

    pub fn getId(self: Self) u32 {
        return switch (self) {
            .ext => self.ext.getId(),
            .pipe => self.pipe.getId(),
            .kern => self.kern.getId(),
        };
    }

    pub fn getMode(self: Self) u16 {
        return switch (self) {
            .ext => self.ext.mode.toU16(),
            .pipe => 511,
            .kern => 511,
        };
    }

    pub fn getLinkCount(self: Self) u16 {
        return switch (self) {
            .ext => self.ext.links_count,
            .pipe => 1,
            .kern => 1,
        };
    }

    pub fn getUid(self: Self) u16 {
        return switch (self) {
            .ext => self.ext.uid,
            .pipe => 0,
            .kern => 0,
        };
    }

    pub fn getGid(self: Self) u16 {
        return switch (self) {
            .ext => self.ext.gid,
            .pipe => 0,
            .kern => 0,
        };
    }

    pub fn getSize(self: Self) usize {
        return switch (self) {
            .ext => self.ext.size,
            .pipe => 0,
            .kern => 0,
        };
    }

    pub fn getBlkSize(self: Self) usize {
        return switch (self) {
            .ext => self.ext.fs.superblock.getBlockSize(),
            .pipe => 0,
            .kern => 0,
        };
    }

    pub fn ioctl(self: Self, cmd: usize, arg: usize) isize {
        const i = @import("../syscalls/ioctl.zig");
        return switch (self) {
            .ext => -i.ENOIOCTLCMD,
            .pipe => -i.ENOIOCTLCMD,
            .kern => self.kern.ioctl(cmd, arg),
        };
    }
};
