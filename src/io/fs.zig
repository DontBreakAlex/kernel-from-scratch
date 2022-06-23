const std = @import("std");
const ext = @import("ext2.zig");
const ata = @import("ata.zig");
const log = @import("../log.zig");
const mem = @import("../memory/mem.zig");
const cache = @import("cache.zig");
const dirent = @import("dirent.zig");
const kernfs = @import("kernfs.zig");
const Mode = @import("mode.zig").Mode;
const Fs = ext.Ext2FS;
const DirEnt = dirent.DirEnt;
const InodeRef = dirent.InodeRef;
const Dentry = dirent.Dentry;

pub var root_fs: *Fs = undefined;
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
        .refcount = 1,
        .inode = .{ .ext = try ext.Inode.create(root_fs, 2) },
        .parent = null,
        .name = undefined,
        .namelen = 0,
        .e_type = .Directory,
        .mount = null,
    };

    // log.format("{s}\n", .{ std.mem.bytesAsValue(Mode, std.mem.asBytes(&root_dirent.inode.ext.mode)) });
}

const fcntl = @import("fcntl.zig");

pub const File = struct {
    const Self = @This();

    refcount: usize,
    dentry: *DirEnt,
    mode: u16,
    offset: usize,

    pub fn create(dentry: *DirEnt, mode: u16) !*Self {
        var self = try mem.allocator.create(Self);
        dentry.take();
        self.* = .{
            .refcount = 1,
            .dentry = dentry,
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
            self.dentry.release();
            mem.allocator.destroy(self);
        }
    }

    pub fn read(self: *Self, buff: []u8) !usize {
        if (!(self.mode == fcntl.O_RDONLY or self.mode == fcntl.O_RDWR))
            return error.NotReadable;
        if (self.dentry.inode.hasOffset()) {
            const ret = try self.dentry.inode.read(buff, self.offset);
            self.offset += ret;
            return ret;
        } else {
            return self.dentry.inode.read(buff, undefined);
        }
    }

    pub fn write(self: *Self, buff: []const u8) !usize {
        if (!(self.mode == fcntl.O_WRONLY or self.mode == fcntl.O_RDWR))
            return error.NotWritable;
        if (self.dentry.inode.hasOffset()) {
            const ret = try self.dentry.inode.write(buff, self.offset);
            self.offset += ret;
            return ret;
        } else {
            return self.dentry.inode.write(buff, undefined);
        }
    }

    pub fn getDents(self: *Self, ptr: [*]Dentry, cnt: *usize) !usize {
        if (self.dentry.e_type != .Directory)
            return error.NotADirectory;
        const ret = try self.dentry.inode.getDents(ptr, cnt, self.offset);
        self.offset += ret;
        return ret;
    }
};
