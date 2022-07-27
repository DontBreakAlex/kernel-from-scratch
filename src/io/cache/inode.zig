const std = @import("std");
const ext2 = @import("../ext2.zig");
const mem = @import("../../memory/mem.zig");
const Ext2FS = ext2.Ext2FS;
const Inode = ext2.Inode;

pub const InodeHeader = struct {
    fs: *Ext2FS,
    id: usize,
};
const InodeMap = std.AutoHashMap(InodeHeader, *Inode);

pub var inodeMap = InodeMap.init(mem.allocator);

pub fn syncAllInodes() !void {
    var iter = inodeMap.iterator();
    while (iter.next()) |inode| {
        if (inode.value_ptr.*.dirty)
            try inode.value_ptr.*.sync();
    }
}
