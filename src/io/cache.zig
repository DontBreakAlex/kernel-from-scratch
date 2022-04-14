const mem = @import("../memory/mem.zig");
const std = @import("std");
const ata = @import("ata.zig");
const ext = @import("ext2.zig");

pub const BLOCK_SIZE = 1024;
const CACHE_SIZE = 512;
const SECTORS_PER_BLOCK = 2;

const AtaDevice = ata.AtaDevice;
const Ext2FS = ext.Ext2FS;
const Inode = ext.Inode;
/// Uniquely identifies a buffer (an ext block)
const BufferHeader = struct {
    lba: u28,
    drive: AtaDevice,
};
const Status = union(enum) { Empty, Unlocked: BufferHeader, Locked: BufferHeader };
const BufferData = struct {
    slice: *[BLOCK_SIZE]u8,
    status: Status,
};
const BufferList = std.TailQueue(BufferData);
const BufferMap = std.AutoHashMap(BufferHeader, *Buffer);

pub const Buffer = BufferList.Node;

pub const InodeHeader = struct {
    fs: *Ext2FS,
    id: usize,
};
const InodeMap = std.AutoHashMap(InodeHeader, *Inode);

pub fn init() !void {
    var buffers = try mem.allocator.alloc([BLOCK_SIZE]u8, CACHE_SIZE);
    for (buffers) |*buff| {
        var buffer = try mem.allocator.create(Buffer);
        buffer.data = .{ .slice = buff, .status = .Empty };
        bufferList.prepend(buffer);
    }
}

/// List of available buffers
var bufferList = BufferList{};
/// List of buffers containing data, indexed by header
var hashMap = BufferMap.init(mem.allocator);

pub fn getBuffer() ?*Buffer {
    // TODO: Remove from hashmap if necessary
    var buffer = bufferList.popFirst() orelse return null;
    if (buffer.data.status == .Unlocked) {
        _ = hashMap.remove(buffer.data.status.Unlocked);
    }
    return buffer;
}

pub fn getOrReadBlock(disk: *AtaDevice, block: usize) !*Buffer {
    const lba: u28 = @intCast(u28, block * SECTORS_PER_BLOCK);
    if (hashMap.get(BufferHeader{ .drive = disk.*, .lba = lba })) |buffer| {
        // Try to lock the block
        if (buffer.data.status == .Unlocked) {
            buffer.data.status = Status{ .Locked = .{ .drive = disk.*, .lba = lba } };
            return buffer;
        } else {
            @panic("Attemp to read locked buffer");
        }
    } else {
        // Alloc new block
        var buffer: *Buffer = getBuffer() orelse return error.OutOfBuffer;
        const buffer_header = BufferHeader{ .drive = disk.*, .lba = lba };
        try hashMap.put(buffer_header, buffer);
        // Assumes that the disk is selected
        try disk.read(buffer.data.slice, lba);
        buffer.data.status = Status{ .Locked = buffer_header };
        return buffer;
    }
}

/// TODO: Put buffer back in free list
pub fn releaseBuffer(buffer: *Buffer) void {
    const status = Status{ .Unlocked = buffer.data.status.Locked };
    buffer.data.status = status;
    bufferList.append(buffer);
}

pub var inodeMap = InodeMap.init(mem.allocator);
