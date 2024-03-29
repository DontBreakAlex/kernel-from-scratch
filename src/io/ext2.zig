pub const Ext2Header = packed struct {
    /// Total number of inodes
    inodes_count: u32,
    /// Total number of blocks
    blocks_count: u32,
    /// Total number of blocks reserved for the superuser
    r_blocks_count: u32,
    /// Number of free blocks, including reserved ones
    free_blocks_count: u32,
    /// Number of free inodes
    free_inodes_count: u32,
    /// Id of the block containing the superblock structure
    first_data_block: u32,
    /// block_size = 1024 << log_block_size
    log_block_size: u32,
    /// if( positive )
    ///     fragmnet size = 1024 << s_log_frag_size;
    /// else
    ///     framgnet size = 1024 >> -s_log_frag_size;
    log_frag_size: u32,
    /// Number of blocks per group
    blocks_per_group: u32,
    /// Number of fragments per group
    frags_per_group: u32,
    /// Number of inodes per group
    inodes_per_group: u32,
    /// Last mount (Unix time)
    mtime: u32,
    /// Last write (Unix time)
    wtime: u32,
    /// Number of mounts since last full check
    mnt_count: u16,
    /// Number of mounts between full checks
    max_mnt_count: u16,
    /// Magic value identifying the file system as ext2 (0xEF53).
    magic: u16,
    /// File system state
    /// 1 => Unmounted cleanly
    /// 2 => Errors detected (Unproperly unmounted)
    state: u16,
    /// What to do when an error is detected
    /// 1 => Ignore
    /// 2 => Remount read-only
    /// 3 => Kernel panic
    errors: u16,
    /// Minor revison level
    minor_rev_level: u16,
    /// Last file system check (Unix time)
    last_check: u32,
    /// Intervel between full checks (Unix time)
    checkinterval: u32,
    /// Indentifier of the OS that created the FS
    /// 0 => Linux
    /// 1 => Hurd
    /// 2 => Masix
    /// 3 => FreeBSD
    /// 4 => Lites
    creator_os: u32,
    /// Revision level
    /// 0 => Old
    /// 1 => Dynamic
    rev_level: u32,
    /// Default user id for reserved blocks
    def_resuid: u16,
    /// Default group id for resered blocks
    def_resguid: u16,
    /// First usable inode for standard files
    first_ino: u32,
    /// Size of the inode structure (in bytes)
    inode_size: u16,
    /// Block group number hosting the superblock structure
    block_group_nr: u16,
    /// Feature compatibility bitmask
    feature_compat: u32,
    /// Feature incompatibility bitmask
    feature_incompat: u32,
    /// Read-only features bitmask
    feature_ro_compat: u32,
    uuid1: u64,
    uuid2: u64,

    pub fn getBlockSize(self: Ext2Header) usize {
        return @as(usize, 1024) << @intCast(u5, self.log_block_size);
    }
};

const BlockGroupDescriptor = packed struct {
    /// Block id of the block bitmap
    block_bitmap: u32,
    /// Block id of the inode bitmap
    inode_bitmap: u32,
    /// Block id of the inode table
    inode_table: u32,
    /// Node of free blocks
    free_blocks_count: u16,
    /// Node of free inodes
    free_inodes_count: u16,
    /// Number of inodes allocated to directories
    used_dirs_count: u16,
    pad: [2]u8,
    reserved: [12]u8,
};

const DiskInode = packed struct {
    /// Format and acces rights
    mode: u16,
    /// User id
    uid: u16,
    /// File size (for regular files only), truncated to 32bits
    size: u32,
    /// Last access (Unix time)
    atime: u32,
    /// Creation time (Unix time)
    ctime: u32,
    /// Last modification (Unix time)
    mtime: u32,
    /// Last access (Unix time)
    dtime: u32,
    /// Group id
    gid: u16,
    /// Hardlink count
    links_count: u16,
    /// Reserved blocks
    /// WARNING: These blocks are 512bytes long (WHY ?!!!)
    blocks: u32,
    /// How to interpre this data
    flags: u32,
    /// OS-dependant value
    osd1: u32,
    /// Blocks containing the data
    block: [12]u32,
    /// Indirect block
    i_block: u32,
    /// Doubly indirect block
    d_block: u32,
    /// Triply indirect block
    t_block: u32,
    /// Generation (used for NFS)
    generation: u32,
    /// Extended attributes
    file_acl: u32,
    /// In revision 1, 32 high bits of the size
    dir_acl: u32,
    /// Address of fragment (unssuported by most implementations)
    faddr: u32,
    /// OS-dependant value
    osd2: [3]u32,
};

pub const DiskDirent = packed struct {
    inode: u32,
    size: u16,
    name_length: u8,
    type_indicator: u8,

    pub fn getName(self: *const DiskDirent) []u8 {
        return @intToPtr([*]u8, @ptrToInt(self) + @sizeOf(DiskDirent))[0..self.name_length];
    }

    pub fn getNext(self: *const DiskDirent) *DiskDirent {
        return @intToPtr(*DiskDirent, @ptrToInt(self) + self.size);
    }
};

pub const DiskDirentIterator = struct {
    first: *DiskDirent,
    current: *DiskDirent,
    last: *DiskDirent,

    pub fn init(data: []u8) DiskDirentIterator {
        const first = @ptrCast(*DiskDirent, data.ptr);
        return DiskDirentIterator{
            .first = first,
            .current = first,
            .last = @intToPtr(*DiskDirent, @ptrToInt(data.ptr) + data.len),
        };
    }

    pub fn next(self: *DiskDirentIterator) ?*DiskDirent {
        if (self.current == self.last)
            return null;
        // Skip node if it is unused
        if (self.current.inode != 0) {
            defer self.current = self.current.getNext();
            return self.current;
        }
        return self.next();
        // return @call(.{ .modifier = .always_tail }, self.next, .{});
    }

    pub fn deinit(self: *const DiskDirentIterator) void {
        mem.allocator.free(@ptrCast([*]u8, self.first)[0 .. @ptrToInt(self.last) - @ptrToInt(self.first)]);
    }
};

const EXT2MAGIC = 0xEF53;

const FIFO: u16 = 0x1000;
const CHARDEV: u16 = 0x2000;
const DIR: u16 = 0x4000;
const BLOCK: u16 = 0x6000;
const REGULAR: u16 = 0x8000;
const SYMLINK: u16 = 0xA000;
const SOCKET: u16 = 0xC000;

pub const Inode = struct {
    const Self = @This();
    const Type = dirent.Type;

    fs: *Ext2FS,
    id: usize,
    mode: Mode,
    links_count: u16,
    blocks: [12]u32,
    i_block: u32,
    d_block: u32,
    t_block: u32,
    size: u32,
    refcount: usize,
    dirty: bool,
    uid: u16,
    gid: u16,

    pub fn rawRead(self: *const Self, dst: []u8, offset: u32) !void {
        if (dst.len + offset > self.size)
            return error.BadAddress; // EFAULT
        var dst_cursor = @as(u32, 0);
        var to_read = dst.len;
        var src_cursor = offset;

        while (to_read != 0) {
            const block_index = src_cursor / cache.BLOCK_SIZE;
            const index_within_block = src_cursor % cache.BLOCK_SIZE;
            var block = try cache.getOrReadBuffer(self.fs.drive, try self.getNthBlock(block_index));
            const will_read = std.math.min(to_read, cache.BLOCK_SIZE - index_within_block);
            std.mem.copy(u8, dst[dst_cursor .. will_read + dst_cursor], block.data.slice[index_within_block .. will_read + index_within_block]);
            defer cache.releaseBuffer(block);
            to_read -= will_read;
            src_cursor += will_read;
            dst_cursor += will_read;
        }
        std.debug.assert(to_read == 0);
    }

    pub fn rawWrite(self: *Self, src: []const u8, offset: u32) !void {
        var slice_cursor = @as(u32, 0);
        var to_write = src.len;
        var disk_cursor = offset;
        self.dirty = true;

        while (to_write != 0) {
            const block_index = disk_cursor / cache.BLOCK_SIZE;
            const index_within_block = disk_cursor % cache.BLOCK_SIZE;
            var block_id = try self.getNthBlock(block_index);
            if (block_id == 0) {
                block_id = try self.fs.allocBlock();
                self.setNthBlock(block_index, block_id);
            }
            var block = try cache.getOrReadBuffer(self.fs.drive, block_id);
            const will_write = std.math.min(to_write, cache.BLOCK_SIZE - index_within_block);
            std.mem.copy(u8, block.data.slice[index_within_block..will_write], src[slice_cursor..will_write]);
            defer cache.releaseBuffer(block);
            to_write -= will_write;
            disk_cursor += will_write;
            slice_cursor += will_write;
            self.size = disk_cursor;
        }
        std.debug.assert(to_write == 0);
    }

    const PTR_PER_BLOCK = cache.BLOCK_SIZE / 4;

    fn getNthBlock(self: *const Self, n: u32) !u32 {
        return switch (n) {
            0...11 => self.blocks[n],
            12...PTR_PER_BLOCK => {
                return self.getNthByteOfBlock(self.i_block, n - 12);
            },
            else => @panic("Unimplemented"),
        };
    }

    fn getNthByteOfBlock(self: *const Self, block: u32, n: u32) !u32 {
        var buffer = try cache.getOrReadBuffer(self.fs.drive, block);
        defer cache.releaseBuffer(buffer);
        var data = std.mem.bytesAsSlice(u32, buffer.data.slice);
        return data[n];
    }

    fn setNthBlock(self: *Self, n: u32, blk: u32) void {
        switch (n) {
            0...11 => self.blocks[n] = blk,
            else => @panic("Unimplemented"),
        }
    }

    pub fn read(self: *Self, buff: []u8, offset: usize) !usize {
        if (offset >= self.size)
            return 0;
        const to_read = std.math.min(buff.len, self.size - offset);
        try self.rawRead(buff[0..to_read], offset);
        return to_read;
    }

    pub fn write(self: *Self, buff: []const u8, offset: usize) !usize {
        try self.rawWrite(buff, offset);
        return buff.len;
    }

    pub fn lookupChild(self: *const Self, name: []const u8, indicator: *u8) !?InodeRef {
        var data = try mem.allocator.alloc(u8, self.size);
        defer mem.allocator.free(data);
        try self.rawRead(data, 0);

        var iter = DiskDirentIterator.init(data);
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, name, entry.getName())) {
                indicator.* = entry.type_indicator;
                return InodeRef{ .ext = try Inode.create(self.fs, entry.inode) };
            }
        }
        return null;
    }

    /// Returns the number of bytes read
    pub fn getDents(self: *const Self, ptr: [*]Dentry, cnt: *usize, offset: usize) !usize {
        if (offset >= self.size) {
            cnt.* = 0;
            return 0;
        }
        const to_read = cache.BLOCK_SIZE - offset % cache.BLOCK_SIZE;
        var data = try mem.allocator.alloc(u8, to_read);
        defer mem.allocator.free(data);
        try self.rawRead(data, offset);

        var iter = DiskDirentIterator.init(data);

        var i: usize = 0;
        var acctually_read: usize = 0;
        var dst = ptr[0..cnt.*];
        while (iter.next()) |entry| {
            if (i >= dst.len)
                break;
            dst[i].inode = entry.inode;
            dst[i].namelen = entry.name_length;
            std.mem.copy(u8, &dst[i].name, entry.getName());
            i += 1;
            acctually_read += entry.size;
        }
        cnt.* = i;
        return acctually_read;
    }

    pub fn currentSize(self: *const Self) usize {
        return self.size;
    }

    /// Caller is responsible to call release() on the inode
    pub fn create(fs: *Ext2FS, inode: usize) !*Self {
        const header = cache.InodeHeader{ .fs = fs, .id = inode };
        if (cache.inodeMap.get(header)) |node| {
            node.acquire();
            return node;
        }
        var node = try mem.allocator.create(Inode);
        errdefer mem.allocator.destroy(node);
        node.* = try fs.readInode(inode);
        try cache.inodeMap.put(header, node);
        return node;
    }

    pub fn acquire(self: *Self) void {
        self.refcount += 1;
    }

    pub fn release(self: *Self) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            if (self.dirty)
                self.sync() catch log.format("/!\\ Failed to sync inode !\n", .{});
            _ = cache.inodeMap.remove(.{ .fs = self.fs, .id = self.id });
            mem.allocator.destroy(self);
        }
    }

    pub fn sync(self: *Self) !void {
        var disk_inode: *DiskInode = undefined;
        var buffer = try self.fs.getDiskInode(&disk_inode, self.id);
        defer cache.releaseBuffer(buffer);
        disk_inode.mode = self.mode.toU16();
        disk_inode.block = self.blocks;
        disk_inode.i_block = self.i_block;
        disk_inode.d_block = self.d_block;
        disk_inode.t_block = self.t_block;
        disk_inode.size = self.size;
        disk_inode.links_count = self.links_count;
        buffer.data.status.Locked.dirty = true;
        self.dirty = false;
    }

    pub fn addChild(self: *Self, name: []const u8, inode: usize, indicator: Type) !void {
        const last_used_blk_index = self.size / self.fs.superblock.getBlockSize() - 1;
        const blk = try cache.getOrReadBuffer(self.fs.drive, try self.getNthBlock(last_used_blk_index));
        defer cache.releaseBuffer(blk);
        var current = @ptrCast(*DiskDirent, blk.data.slice); // TODO: Reuse released blocks
        while (@ptrToInt(current) + current.size != @ptrToInt(blk.data.slice) + blk.data.slice.len)
            current = current.getNext();
        const real_size = std.mem.alignForward(@sizeOf(DiskDirent) + current.name_length, 4);
        const available_size = current.size - real_size;
        const required_size = std.mem.alignForward(@sizeOf(DiskDirent) + name.len, 4);
        if (available_size >= required_size) {
            current.size = @intCast(u16, real_size);
            var new = current.getNext();
            new.inode = inode;
            new.name_length = @intCast(u8, name.len);
            new.size = @intCast(u16, available_size);
            new.type_indicator = indicator.toTypeIndicator();
            std.mem.copy(u8, new.getName(), name);
            blk.data.status.Locked.dirty = true;
        } else {
            const new_blk_id = try self.fs.allocBlock();
            const new_blk = try cache.getOrReadBuffer(self.fs.drive, new_blk_id);
            new_blk.data.status.Locked.dirty = true;
            defer cache.releaseBuffer(new_blk);
            var new = @ptrCast(*DiskDirent, blk.data.slice);
            new.inode = inode;
            new.name_length = @intCast(u8, name.len);
            new.size = @intCast(u16, available_size);
            new.type_indicator = indicator.toTypeIndicator();
            std.mem.copy(u8, new.getName(), name);
        }
    }

    /// Caller is responsible to call release() on the inode
    pub fn createChild(self: *Self, name: []const u8, e_type: Type, mode: Mode) !*Inode {
        var inode = try self.fs.allocInode();
        // TODO: Delete on failure
        inode.mode = mode;
        inode.size = 0;
        inode.links_count = 1;
        try self.addChild(name, inode.id, e_type);
        return inode;
    }

    pub fn getDevId(self: *const Self) usize {
        return @ptrToInt(self.fs.superblock);
    }

    pub fn getId(self: *const Self) u32 {
        return self.id;
    }
};

const cache = @import("cache.zig");
const ata = @import("ata.zig");
const serial = @import("../serial.zig");
const mem = @import("../memory/mem.zig");
const log = @import("../log.zig");
const utils = @import("../utils.zig");
const std = @import("std");
const dirent = @import("dirent.zig");

const AtaDevice = ata.AtaDevice;
const DirEnt = dirent.DirEnt;
const Dentry = dirent.Dentry;
const InodeRef = dirent.InodeRef;
const Buffer = cache.Buffer;
const Mode = @import("mode.zig").Mode;

pub const Ext2FS = struct {
    drive: *AtaDevice,
    superblock: *Ext2Header,
    block_group_descriptor_table: []BlockGroupDescriptor,
    sblock_buffer: *Buffer,
    bgd_buffer: *Buffer,

    /// Finds a disk inode. The pointer has the same lifetime as the returned buffer. The buffer must be released by the caller.
    fn getDiskInode(self: *Ext2FS, ptr: **DiskInode, inode: usize) !*Buffer {
        const index = inode - 1;
        const group = index / self.superblock.inodes_per_group;
        const offset_in_group = index % self.superblock.inodes_per_group;
        const group_descriptor = &self.block_group_descriptor_table[group];
        const inode_block = group_descriptor.inode_table + offset_in_group * self.superblock.inode_size / self.superblock.getBlockSize();
        const inode_buffer = try cache.getOrReadBuffer(self.drive, inode_block);
        const inodes_per_block = self.superblock.getBlockSize() / self.superblock.inode_size;
        const inodes = @ptrCast([*]DiskInode, inode_buffer.data.slice)[0..inodes_per_block];
        ptr.* = &inodes[offset_in_group % inodes_per_block];
        return inode_buffer;
    }

    fn readInode(self: *Ext2FS, inode: usize) !Inode {
        var node: *DiskInode = undefined;
        const buffer = try self.getDiskInode(&node, inode);
        defer cache.releaseBuffer(buffer);

        return Inode{
            .fs = self,
            .id = inode,
            .mode = std.mem.bytesToValue(Mode, std.mem.asBytes(&node.mode)),
            .blocks = node.block,
            .i_block = node.i_block,
            .d_block = node.d_block,
            .t_block = node.t_block,
            .size = node.size,
            .links_count = node.links_count,
            .refcount = 1,
            .dirty = false,
            .uid = node.uid,
            .gid = node.gid,
        };
    }

    /// Caller is responsible to call release() on the inode
    pub fn allocInode(self: *Ext2FS) !*Inode {
        for (self.block_group_descriptor_table) |*descriptor, d| {
            if (descriptor.free_inodes_count != 0) {
                const bitmap_blk = try cache.getOrReadBuffer(self.drive, descriptor.inode_bitmap);
                defer cache.releaseBuffer(bitmap_blk);
                const bitmap = bitmap_blk.data.slice;
                std.debug.assert(bitmap.len >= self.superblock.inodes_per_group / 8);
                var i: usize = 0;
                while (i < self.superblock.inodes_per_group / 8) : (i += 1) {
                    if (bitmap[i] != 255) {
                        var o: u3 = 0;
                        while (o < 8) : (o += 1) {
                            const mask = @as(u8, 1) << o;
                            if (bitmap[i] & mask == 0) {
                                bitmap[i] &= mask;
                                descriptor.free_inodes_count -= 1;
                                self.bgd_buffer.data.status.Locked.dirty = true;
                                self.superblock.free_inodes_count -= 1;
                                self.sblock_buffer.data.status.Locked.dirty = true;
                                bitmap_blk.data.status.Locked.dirty = true;
                                const id = d * self.superblock.inodes_per_group + i * 8 + o + 1;
                                var inode = try Inode.create(self, id);
                                inode.dirty = true;
                                return inode;
                            }
                        }
                    }
                }
            }
        }
        return error.OufOfSpace;
    }

    pub fn allocBlock(self: *Ext2FS) !u32 {
        for (self.block_group_descriptor_table) |*descriptor, d| {
            if (descriptor.free_blocks_count != 0) {
                const bitmap_blk = try cache.getOrReadBuffer(self.drive, descriptor.block_bitmap);
                defer cache.releaseBuffer(bitmap_blk);
                const bitmap = bitmap_blk.data.slice;
                std.debug.assert(bitmap.len >= self.superblock.blocks_per_group / 8);
                var i: usize = 0;
                while (i < self.superblock.blocks_per_group) : (i += 1) {
                    if (bitmap[i] != 255) {
                        var o: u3 = 0;
                        while (o < 8) : (o += 1) {
                            const mask = @as(u8, 1) << o;
                            if (bitmap[i] & mask == 0) {
                                bitmap[i] &= mask;
                                descriptor.free_blocks_count -= 1;
                                self.bgd_buffer.data.status.Locked.dirty = true;
                                self.superblock.free_blocks_count -= 1;
                                self.sblock_buffer.data.status.Locked.dirty = true;
                                bitmap_blk.data.status.Locked.dirty = true;
                                const id = d * self.superblock.blocks_per_group + i * 8 + o + self.superblock.first_data_block;
                                return id;
                            }
                        }
                    }
                }
            }
        }
        return error.OufOfSpace;
    }

    pub fn sync(self: *Ext2FS) !void {
        if (!self.sblock_buffer.data.status.Locked.dirty and !self.bgd_buffer.data.status.Locked.dirty)
            return;
        if (self.sblock_buffer.data.status.Locked.dirty) {
            const header = self.sblock_buffer.data.status.Locked.header;
            try header.drive.write(self.sblock_buffer.data.slice, header.lba);
        }
        if (self.bgd_buffer.data.status.Locked.dirty) {
            const header = self.bgd_buffer.data.status.Locked.header;
            try header.drive.write(self.bgd_buffer.data.slice, header.lba);
        }
        if (self.block_group_descriptor_table.len > 1) {
            try self.saveToBlockGroup(1);
        }
        var i: usize = 3;
        while (i < self.block_group_descriptor_table.len) : (i *= 3) {
            try self.saveToBlockGroup(i);
        }
        i = 5;
        while (i < self.block_group_descriptor_table.len) : (i *= 5) {
            try self.saveToBlockGroup(i);
        }
        i = 7;
        while (i < self.block_group_descriptor_table.len) : (i *= 7) {
            try self.saveToBlockGroup(i);
        }
        self.sblock_buffer.data.status.Locked.dirty = false;
        self.bgd_buffer.data.status.Locked.dirty = false;
    }

    fn saveToBlockGroup(self: *Ext2FS, id: usize) !void {
        const sblock_buffer = try cache.getOrReadBuffer(self.drive, self.superblock.first_data_block + id * self.superblock.blocks_per_group);
        defer cache.releaseBuffer(sblock_buffer);
        const superblock = @ptrCast(*Ext2Header, sblock_buffer.data.slice);
        // Sanity-check: are we writing the correct block ?
        std.debug.assert(superblock.magic == 0xEF53);
        superblock.* = self.superblock.*;
        sblock_buffer.data.status.Locked.dirty = true;

        const bgd_buffer = try cache.getOrReadBuffer(self.drive, self.superblock.first_data_block + id * self.superblock.blocks_per_group + 1);
        defer cache.releaseBuffer(bgd_buffer);
        const bgd = @ptrCast([*]BlockGroupDescriptor, bgd_buffer.data.slice)[0..self.block_group_descriptor_table.len];
        // Same
        std.debug.assert(bgd[0].block_bitmap == self.block_group_descriptor_table[0].block_bitmap);
        std.mem.copy(BlockGroupDescriptor, bgd, self.block_group_descriptor_table);
        bgd_buffer.data.status.Locked.dirty = true;
    }
};

pub fn create(drive: *AtaDevice) !*Ext2FS {
    const sblock_buffer = try cache.getOrReadBuffer(drive, 1);
    errdefer cache.releaseBuffer(sblock_buffer);

    var fs: *Ext2FS = try mem.allocator.create(Ext2FS);
    errdefer mem.allocator.destroy(fs);

    fs.drive = drive;
    fs.sblock_buffer = sblock_buffer;
    fs.superblock = @ptrCast(*Ext2Header, sblock_buffer.data.slice);
    if (fs.superblock.magic != EXT2MAGIC)
        return error.NotExt2;

    if (fs.superblock.feature_incompat != 0x02) {
        log.format("Unsuported feature flags in ext2 fs: expected 0x02, found 0x{x:0>2}\n", .{fs.superblock.feature_incompat});
        return error.UnsuportedFeatures;
    }
    const blk_size = fs.superblock.getBlockSize();
    if (blk_size != cache.BLOCK_SIZE) {
        log.format("Unsupported block size in ext2 fs: expected {d}, found {d}\n", .{ cache.BLOCK_SIZE, blk_size });
        return error.UnsuportedBlkSize;
    }

    const blkgrp_cnt1 = utils.divCeil(fs.superblock.blocks_count, fs.superblock.blocks_per_group);
    const blkgrp_cnt2 = utils.divCeil(fs.superblock.inodes_count, fs.superblock.inodes_per_group);

    if (blkgrp_cnt1 != blkgrp_cnt2) {
        log.format("Incoherent block group count in ext2 fs\n", .{});
        return error.IncoherentBlkSize;
    }
    if (blkgrp_cnt1 > blk_size / 32) {
        log.format("To many block group descriptors in ext2 fs\n", .{});
        return error.ToManyBlockGroups;
    }

    const bgd_buffer = try cache.getOrReadBuffer(drive, fs.superblock.first_data_block + 1);
    fs.bgd_buffer = bgd_buffer;
    fs.block_group_descriptor_table = @ptrCast([*]BlockGroupDescriptor, bgd_buffer.data.slice)[0..blkgrp_cnt1];

    return fs;
}
