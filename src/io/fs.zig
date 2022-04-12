const std = @import("std");
const ext = @import("ext2.zig");
const ata = @import("ata.zig");
const log = @import("../log.zig");
const mem = @import("../memory/mem.zig");
const cache = @import("cache.zig");
const dirent = @import("dirent.zig");
const Fs = ext.Ext2FS;
const DirEnt = dirent.DirEnt;
const InodeRef = dirent.InodeRef;

var root_fs: *Fs = undefined;
pub var root_dirent: DirEnt = undefined;

pub fn init() !void {
    root_fs = blk: {
        if (ata.disk1.select().srv == 1) {
            if (ext.create(&ata.disk1)) |fs| {
                break :blk fs;
            } else |_| {}
        }
        if (ata.disk2.select().srv == 1) {
            if (ext.create(&ata.disk2)) |fs| {
                break :blk fs;
            } else |_| {}
        }
        if (ata.disk3.select().srv == 1) {
            if (ext.create(&ata.disk3)) |fs| {
                break :blk fs;
            } else |_| {}
        }
        if (ata.disk4.select().srv == 1) {
            if (ext.create(&ata.disk4)) |fs| {
                break :blk fs;
            } else |_| {}
        }
        @panic("Failed to find root dev");
    };

    root_dirent = DirEnt{
        .inode = .{ .ext = try cache.getOrReadInode(root_fs, 2) },
        .parent = null,
        .name = undefined,
        .namelen = 0,
        .e_type = .Directory,
        .children = null,
    };
}

pub const READ: u8 = 0x1;
pub const WRITE: u8 = 0x2;
pub const RW: u8 = 0x3;

pub const File = struct {
    const Self = @This();

    refcount: usize,
    inode: InodeRef,
    mode: u8,
    offset: usize,

    pub fn create(inode: InodeRef, mode: u8) !*Self {
        var self = try mem.allocator.create(Self);
        inode.take();
        self.* = .{
            .refcount = 1,
            .inode = inode,
            .mode = mode,
            .offset = 0,
        };
        return self;
    }

    pub fn dup(self: *Self) void {
        self.refcount += 1;
    }

    pub fn close(self: *Self) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            self.inode.release();
            mem.allocator.destroy(self);
        }
    }

    pub fn read(self: *Self, buff: []u8) !usize {
        if (self.mode & READ == 0)
            return error.NotReadable;
        if (self.inode.hasOffset()) {
            const ret = try self.inode.read(buff, self.offset);
            self.offset += ret;
            return ret;
        } else {
            return self.inode.read(buff, undefined);
        }
    }

    pub fn write(self: *Self, buff: []const u8) !usize {
        if (self.mode & WRITE == 0)
            return error.NotWritable;
        if (self.inode.hasOffset()) {
            const ret = try self.inode.write(buff, self.offset);
            self.offset += ret;
            return ret;
        } else {
            return self.inode.write(buff, undefined);
        }
    }
};
