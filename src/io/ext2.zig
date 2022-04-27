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

    fs: *Ext2FS,
    id: usize,
    mode: u16,
    blocks: [12]u32,
    i_block: u32,
    d_block: u32,
    t_block: u32,
    size: u32,
    refcount: usize,

    pub fn rawRead(self: *const Self, dst: []u8, offset: u32) !void {
        if (dst.len + offset > self.size)
            return error.BufferTooLong;
        var dst_cursor = @as(u32, 0);
        var to_read = dst.len;
        var src_cursor = offset;

        while (to_read != 0) {
            const block_index = src_cursor / cache.BLOCK_SIZE;
            const index_within_block = src_cursor % cache.BLOCK_SIZE;
            var block = try cache.getOrReadBlock(self.fs.drive, self.getNthBlock(block_index));
            const will_read = std.math.min(to_read, cache.BLOCK_SIZE - index_within_block);
            std.mem.copy(u8, dst[dst_cursor..will_read], block.data.slice[index_within_block..will_read]);
            defer cache.releaseBuffer(block);
            to_read -= will_read;
            src_cursor += will_read;
            dst_cursor += will_read;
        }
        std.debug.assert(to_read == 0);
    }

    fn getNthBlock(self: *const Self, n: u32) u32 {
        return switch (n) {
            0...11 => self.blocks[n],
            else => @panic("Unimplemented"),
        };
    }

    pub fn read(self: *Self, buff: []u8, offset: usize) !usize {
        if (offset >= self.size)
            return 0;
        const to_read = std.math.min(buff.len, self.size - offset);
        try self.rawRead(buff[0..to_read], offset);
        return to_read;
    }

    pub fn populateChildren(self: *const Self, dentry: *DirEnt) !void {
        var data = try mem.allocator.alloc(u8, self.size);
        defer mem.allocator.free(data);
        try self.rawRead(data, 0);

        var iter = DiskDirentIterator.init(data);
        dentry.children = dirent.Childrens{};
        // TODO: Correct free after error
        while (iter.next()) |entry| {
            var e_type = try dirent.Type.fromTypeIndicator(entry.type_indicator);
            var child = try mem.allocator.create(dirent.Child);
            child.data = try DirEnt.create(.{ .ext = try Inode.create(self.fs, entry.inode) }, dentry, entry.getName(), e_type);
            dentry.children.?.append(child);
        }
    }

    pub fn currentSize(self: *const Self) usize {
        return self.size;
    }

    pub fn create(fs: *Ext2FS, inode: usize) !*Self {
        const header = cache.InodeHeader{ .fs = fs, .id = inode };
        if (cache.inodeMap.get(header)) |node| {
            node.take();
            return node;
        }
        var node = try mem.allocator.create(Inode);
        errdefer mem.allocator.destroy(node);
        node.* = try fs.readInode(inode);
        try cache.inodeMap.put(header, node);
        return node;
    }

    pub fn take(self: *Self) void {
        self.refcount += 1;
    }

    pub fn release(self: *Self) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            _ = cache.inodeMap.remove(.{ .fs = self.fs, .id = self.id });
            mem.allocator.destroy(self);
        }
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

pub const Ext2FS = struct {
    drive: *AtaDevice,
    superblock: *Ext2Header,
    block_group_descriptor_table: []BlockGroupDescriptor,

    pub fn readInode(self: *Ext2FS, inode: usize) !Inode {
        const index = inode - 1;
        const group = index / self.superblock.inodes_per_group;
        const offset_in_group = index % self.superblock.inodes_per_group;
        const group_descriptor = &self.block_group_descriptor_table[group];
        const inode_block = group_descriptor.inode_table + offset_in_group * self.superblock.inode_size / self.superblock.getBlockSize();
        const inode_buffer = try cache.getOrReadBlock(self.drive, inode_block);
        defer cache.releaseBuffer(inode_buffer);
        const inodes_per_block = self.superblock.getBlockSize() / self.superblock.inode_size;
        const inodes = @ptrCast([*]DiskInode, inode_buffer.data.slice)[0..inodes_per_block];
        const node = inodes[offset_in_group % inodes_per_block];
        // serial.format("{}\n", .{node.size});
        return Inode{
            .fs = self,
            .id = inode,
            .mode = node.mode,
            .blocks = node.block,
            .i_block = node.i_block,
            .d_block = node.d_block,
            .t_block = node.t_block,
            .size = node.size,
            .refcount = 1,
        };
    }
};

pub fn create(drive: *AtaDevice) !*Ext2FS {
    const sblock_buffer = try cache.getOrReadBlock(drive, 1);
    errdefer cache.releaseBuffer(sblock_buffer);

    var fs: *Ext2FS = try mem.allocator.create(Ext2FS);
    errdefer mem.allocator.destroy(fs);

    fs.drive = drive;
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

    const bgd_talbe_offset: u28 = if (blk_size == 1024) 2 else 1;
    const bgd_buffer = try cache.getOrReadBlock(drive, bgd_talbe_offset);
    fs.block_group_descriptor_table = @ptrCast([*]BlockGroupDescriptor, bgd_buffer.data.slice)[0..blkgrp_cnt1];

    return fs;
}
