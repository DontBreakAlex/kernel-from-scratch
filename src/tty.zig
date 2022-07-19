const utils = @import("utils.zig");
const vga = @import("vga.zig");
const scheduler = @import("scheduler.zig");
const kernfs = @import("io/kernfs.zig");

const Buffer = utils.Buffer;

var buffer = Buffer.init();
pub var inode = kernfs.Inode{
    .refcount = 1,
    .kind = .{
        .Device = .{
            .write = undefined,
            .rawWrite = undefined,
            .read = read,
            .rawRead = undefined
        }
    }
};

pub fn recieve(buff: []const u8) void {
    buffer.write(buff) catch vga.putStr("Could not handle keypress\n");
    if (scheduler.events.getPtr(.{ .IO_WRITE = .{ .kern = &inode } })) |array| {
        if (array.items.len == 0)
            @panic("Check");
        scheduler.queue.write(array.items) catch unreachable;
        array.clearRetainingCapacity();
    }
}

fn read(dst: []u8) usize {
    while (buffer.readableLength() == 0) {
        scheduler.waitForEvent(.{ .IO_WRITE = .{ .kern = &inode } }) catch unreachable;
    }
    return buffer.read(dst);
}
