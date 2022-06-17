const std = @import("std");
const mem = @import("../../memory/mem.zig");

const CACHE_SIZE = 512;
const SECTORS_PER_BLOCK = 2;
const BLOCK_SIZE = @import("constants.zig").BLOCK_SIZE;

const AtaDevice = @import("../ata.zig").AtaDevice;

/// Uniquely identifies a buffer (an ext block)
const BufferHeader = struct {
    lba: u28,
    drive: AtaDevice,
};
const BufferStatus = struct { header: BufferHeader, dirty: bool };
const Status = union(enum) { Empty, Unlocked: BufferStatus, Locked: BufferStatus };
const BufferData = struct {
    slice: *[BLOCK_SIZE]u8,
    status: Status,
};
const BufferList = std.TailQueue(BufferData);
const BufferMap = std.AutoHashMap(BufferHeader, *Buffer);
pub const Buffer = BufferList.Node;

/// List of available buffers
var bufferList = BufferList{};
/// List of buffers containing data, indexed by header
var hashMap = BufferMap.init(mem.allocator);

pub fn init() !void {
    var buffers = try mem.allocator.alloc([BLOCK_SIZE]u8, CACHE_SIZE);
    for (buffers) |*buff| {
        var buffer = try mem.allocator.create(Buffer);
        buffer.data = .{ .slice = buff, .status = .Empty };
        bufferList.prepend(buffer);
    }
}

pub fn getAvailableBuffer() ?*Buffer {
    var buffer = bufferList.pop() orelse return null;
    if (buffer.data.status == .Unlocked) {
        // TODO: Write buffer to disk
        if (buffer.data.status.Unlocked.dirty == true)
            @panic("Buffer cache full !!!");
        _ = hashMap.remove(buffer.data.status.Unlocked.header);
    }
    return buffer;
}

/// Buffer that are held will not be written to disk even if they are dirty. The owner must write them himself if they need to be written back.
pub fn getOrReadBuffer(disk: *AtaDevice, block: usize) !*Buffer {
    const lba: u28 = @intCast(u28, block * SECTORS_PER_BLOCK);
    if (hashMap.get(BufferHeader{ .drive = disk.*, .lba = lba })) |buffer| {
        // Try to lock the block
        if (buffer.data.status == .Unlocked) {
            bufferList.remove(buffer);
            const status = Status{ .Locked = buffer.data.status.Unlocked };
            buffer.data.status = status;
            return buffer;
        } else {
            @panic("Attemp to read locked buffer");
        }
    } else {
        // Alloc new block
        var buffer: *Buffer = getAvailableBuffer() orelse return error.OutOfBuffer;
        const buffer_header = BufferHeader{ .drive = disk.*, .lba = lba };
        try hashMap.put(buffer_header, buffer);
        // Assumes that the disk is selected
        try disk.read(buffer.data.slice, lba);
        buffer.data.status = Status{ .Locked = .{ .header = buffer_header, .dirty = false } };
        return buffer;
    }
}

pub fn releaseBuffer(buffer: *Buffer) void {
    var status = Status{ .Unlocked = buffer.data.status.Locked };
    buffer.data.status = status;
    bufferList.prepend(buffer);
}

/// Buffer must be unlocked
fn writeBuffer(buffer: *Buffer) !void {
    std.debug.assert(buffer.data.status == .Unlocked);
    const header = buffer.data.status.Unlocked.header;
    try header.drive.write(buffer.data.slice, header.lba);
    buffer.data.status.Unlocked.dirty = false;
}

/// Returns the argument to be passed to the first call of syncOne
pub inline fn syncBuffersInit() ?*Buffer {
    return bufferList.last;
}

/// Should be recalled with its return value until it returns null to sync all buffers
pub fn syncOneBuffer(begin_at: *Buffer) ?*Buffer {
    var current: ?*Buffer = begin_at;
    while (current) |c| {
        if (c.data.status == .Unlocked)
            if (c.data.status.Unlocked.dirty)
                break;
        current = c.prev;
    }
    if (current) |buffer| {
        writeBuffer(buffer) catch @panic("Failed to write buffer back to disk\n");
        return buffer.prev;
    }
    return null;
}

pub fn syncAllBuffers() void {
    var last_call = syncBuffersInit();
    while (last_call) |call|
        last_call = syncOneBuffer(call);
}
