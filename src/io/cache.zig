const mem = @import("../memory/mem.zig");
const std = @import("std");
const ata = @import("ata.zig");

pub const BLOCK_SIZE = 1024;
const CACHE_SIZE = 512;
const SECTORS_PER_BLOCK = 2;
const AtaDevice = ata.AtaDevice;
const BufferHeader = struct {
    lba: u28,
    drive: AtaDevice,
};
const List = std.TailQueue(struct {
    slice: *[BLOCK_SIZE]u8,
    status: Status,
});
pub const Buffer = List.Node;
const HashMap = std.AutoHashMap(BufferHeader, *Buffer);
const Status = union(enum) { Empty, Unlocked: BufferHeader, Locked: BufferHeader };
var freeList = List{};
var hashMap = HashMap.init(mem.allocator);

pub fn init() !void {
    var buffers = try mem.allocator.alloc([BLOCK_SIZE]u8, CACHE_SIZE);
    for (buffers) |*buff| {
        var buffer = try mem.allocator.create(Buffer);
        buffer.data = .{ .slice = buff, .status = .Empty };
        freeList.prepend(buffer);
    }
}

pub fn getBuffer() ?*Buffer {
    // TODO: Remove from hashmap if necessary
    return freeList.popFirst();
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
        disk.read(buffer.data.slice, lba);
        buffer.data.status = Status{ .Locked = buffer_header };
        return buffer;
    }
}

/// TODO: Put buffer back in free list
pub fn releaseBuffer(buffer: *Buffer) void {
    buffer.data.status = .Unlocked;
}

// TODO: Free old buffers
