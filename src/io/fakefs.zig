const utils = @import("../utils.zig");
const dirent = @import("dirent.zig");
const scheduler = @import("../scheduler.zig");
const mem = @import("../memory/mem.zig");

const Buffer = utils.Buffer;
const DirEnt = dirent.DirEnt;
const Event = scheduler.Event;

pub const Inode = struct {
    const Self = @This();

    buffer: Buffer,
    refcount: usize,

    pub fn create() !*Self {
        const self = try mem.allocator.create(Self);
        self.* = .{
            .refcount = 1,
            .buffer = Buffer.init(),
        };
        return self;
    }

    pub fn take(self: *Self) void {
        self.refcount += 1;
    }

    pub fn release(self: *Self) void {
        self.refcount -= 1;
        if (self.refcount == 0)
            mem.allocator.destroy(self);
    }

    pub fn read(self: *Self, buff: []u8) !usize {
        while (self.buffer.readableLength() == 0) {
            scheduler.waitForEvent(Event{ .IO_WRITE = .{ .fake = self } });
        }
        return scheduler.readWithEvent(.{ .fake = self }, buff, undefined);
    }

    pub fn rawRead(self: *Self, buff: []u8) !usize {
        return self.buffer.read(buff);
    }

    pub fn write(self: *Self, buff: []const u8) !void {
        return scheduler.writeWithEvent(.{ .fake = self }, buff, undefined);
    }

    pub fn rawWrite(self: *Self, buff: []const u8) !void {
        return self.buffer.write(buff);
    }

    pub fn populateChildren(self: *const Self, dentry: *DirEnt) !void {
        _ = self;
        dentry.children = dirent.Child{};
    }

    pub fn currentSize(self: *const Self) usize {
        return self.buffer.readableLength();
    }
};
