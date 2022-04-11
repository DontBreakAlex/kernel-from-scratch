const utils = @import("../utils.zig");
const dirent = @import("dirent.zig");

const Buffer = utils.Buffer;
const DirEnt = dirent.DirEnt;

pub const Inode = struct {
    const Self = @This();

    buffer: *Buffer,

    pub fn read(self: *const Self, buff: []u8) !usize {
        return buffer.read(buff);
    }

    pub fn write(self: *const Self, buff: []u8) !usize {
        return buffer.write(buff);
    }

    pub fn populateChildren(self: *const Self, dentry: *DirEnt) !void {
        dentry.children = dirent.Child{};
    }

    pub fn currentSize(self: *const Self) usize {
        return self.buffer.readableLength();
    }
};
