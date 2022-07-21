const utils = @import("utils.zig");
const vga = @import("vga.zig");
const scheduler = @import("scheduler.zig");
const kernfs = @import("io/kernfs.zig");
const std = @import("std");

const Buffer = utils.Buffer;

var bufferIn = Buffer.init();
// zig fmt: off
pub var inode = kernfs.Inode{
    .refcount = 1,
    .kind = .{
        .Device = .{
            .write = write,
            .rawWrite = undefined,
            .read = read,
            .rawRead = undefined
        }
    }
};

pub fn recieve(buff: []const u8) void {
    bufferIn.write(buff) catch vga.putStr("Could not handle keypress\n");
    if (scheduler.events.getPtr(.{ .IO_WRITE = .{ .kern = &inode } })) |array| {
        if (array.items.len == 0)
            @panic("Check");
        scheduler.queue.write(array.items) catch unreachable;
        array.clearRetainingCapacity();
    }
}

fn read(dst: []u8) usize {
    while (bufferIn.readableLength() == 0) {
        scheduler.waitForEvent(.{ .IO_WRITE = .{ .kern = &inode } }) catch unreachable;
    }
    return bufferIn.read(dst);
}

var bufferOut = std.fifo.LinearFifo(u8, std.fifo.LinearFifoBufferType{ .Static = 512 }).init();

pub fn write(src: []const u8) usize {
    bufferOut.write(src) catch unreachable;
    consume();
    return src.len;
}

fn consume() void {
    while (bufferOut.readableLength() > 0) {
        if (bufferOut.peekItem(0) == 0x1B) {
            var slice = bufferOut.readableSlice(0);
            if (slice.len < 2)
                break;
            if (slice[1] == '[') {
                var params: usize = 2;
                while (params < slice.len and slice[params] >= 0x30 and slice[params] <= 0x3F)
                    params += 1;
                var intermediate = params;
                while (intermediate < slice.len and slice[intermediate] >= 0x20 and slice[intermediate] <= 0x2F)
                    intermediate += 1;
                const final = intermediate;
                if (final >= slice.len)
                    break;
                if (slice[final] >= 0x40 and slice[final] <= 0x7F) {
                    out: {
                        handleEscapeCode(slice[2..params], slice[params..intermediate], slice[final]) catch break :out;
                        bufferOut.discard(final + 1);
                        continue;
                    }
                }
            }
        }
        vga.putChar(bufferOut.readItem() orelse unreachable);
    }
}

fn handleEscapeCode(params: []const u8, intermediate: []const u8, final: u8) !void {
    // vga.format("Params: '{s}'\nInter: '{s}'\nFinal: '{}'\n", .{ params, intermediate, final });
    _ = intermediate;
    switch (final) {
        'A' => {
            var count = try std.fmt.parseInt(usize, params, 10);
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.up();
            vga.CURSOR.update();
        },
        'B' => {
            var count = try std.fmt.parseInt(usize, params, 10);
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.down();
            vga.CURSOR.update();
        },
        'C' => {
            var count = try std.fmt.parseInt(usize, params, 10);
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.left();
            vga.CURSOR.update();
        },
        'D' => {
            var count = try std.fmt.parseInt(usize, params, 10);
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.right();
            vga.CURSOR.update();
        },
        'E' => {
            var count = try std.fmt.parseInt(usize, params, 10);
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.newline();
            vga.CURSOR.update();
        },
        'H' => {
            var iter = std.mem.tokenize(u8, params, ";");
            const row = try std.fmt.parseInt(u8, iter.next() orelse return error.NotEnouthArgs, 10);
            const column = try std.fmt.parseInt(u8, iter.next() orelse return error.NotEnouthArgs, 10);
            vga.CURSOR.goto(row, column);
        },
        'J' => {
            const arg = try std.fmt.parseInt(usize, params, 10);
            if (arg == 2 or arg == 3) {
                _ = vga.clear();
                return;
            }
            return error.UnknownCommand;
        },
        else =>  {
            return error.UnknownCommand;
        }
    }
}

pub const Writer = std.io.Writer(void, anyerror, write);

pub fn format(comptime fmt: []const u8, args: anytype) void {
    std.fmt.format(Writer{ .context = {} }, fmt, args) catch {};
}