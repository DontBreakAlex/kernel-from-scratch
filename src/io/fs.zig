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

const File = struct {
    refcount: usize,
    inode: InodeRef,
    mode: u8,
    offset: usize,
};
