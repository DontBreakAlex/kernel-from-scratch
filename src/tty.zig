const utils = @import("utils.zig");
const vga = @import("vga.zig");
const scheduler = @import("scheduler.zig");
const kernfs = @import("io/kernfs.zig");
const std = @import("std");
const termio = @import("io/termio.zig");
const errno = @import("syscalls/errno.zig");
const inoderef = @import("io/inoderef.zig");
const serial = @import("serial.zig");

const Buffer = utils.Buffer;
const Cursor = @import("cursor.zig").Cursor;
const Status = inoderef.Status;
const ENOIOCTLCMD = @import("syscalls/ioctl.zig").ENOIOCTLCMD;

var bufferIn = Buffer.init();
// zig fmt: off
pub var inode = kernfs.Inode{
    .refcount = 1,
    .kind = .{
        .Device = .{
            .write = write,
            .rawWrite = undefined,
            .read = read,
            .rawRead = undefined,
            .ioctl = ioctl,
            .poll = poll,
        }
    }
};

pub fn recieve(buff: []const u8) void {
    bufferIn.write(buff) catch vga.putStr("Could not handle keypress\n");
    if (scheduler.events.getPtr(.{ .IO_WRITE = .{ .kern = &inode } })) |array| {
        // if (array.items.len == 0)
        //     @panic("Check");
        var iter = array.iterator();
        while (iter.next()) |pair| {
            scheduler.queue.writeItem(pair.key_ptr.*) catch unreachable;
        }
        array.clearRetainingCapacity();
    }
}

pub fn recieveItem(buff: u8) void {
    bufferIn.writeItem(buff) catch vga.putStr("Could not handle keypress\n");
    if (scheduler.events.getPtr(.{ .IO_WRITE = .{ .kern = &inode } })) |array| {
        // if (array.items.len == 0)
        //     @panic("Check");
        var iter = array.iterator();
        while (iter.next()) |pair| {
            scheduler.queue.writeItem(pair.key_ptr.*) catch unreachable;
        }
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

var cursor = Cursor{ .x = 0, .y = 0 };

fn handleEscapeCode(params: []const u8, intermediate: []const u8, final: u8) !void {
    // vga.format("Params: '{s}'\nInter: '{s}'\nFinal: '{}'\n", .{ params, intermediate, final });
    _ = intermediate;
    switch (final) {
        'A' => {
            var count = if (params.len != 0) try std.fmt.parseInt(usize, params, 10) else 1;
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.up();
            vga.CURSOR.update();
        },
        'B' => {
            var count = if (params.len != 0) try std.fmt.parseInt(usize, params, 10) else 1;
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.down();
            vga.CURSOR.update();
        },
        'C' => {
            var count = if (params.len != 0) try std.fmt.parseInt(usize, params, 10) else 1;
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.left();
            vga.CURSOR.update();
        },
        'D' => {
            var count = if (params.len != 0) try std.fmt.parseInt(usize, params, 10) else 1;
            while (count != 0) : (count -= 1)
                _ = vga.CURSOR.right();
            vga.CURSOR.update();
        },
        'E' => {
            var count = if (params.len != 0) try std.fmt.parseInt(usize, params, 10) else 1;
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
        'P' => {
            vga.erase();
        },
        's' => {
            cursor = vga.CURSOR;
        },
        'u' => {
            vga.CURSOR = cursor;
        },
        else =>  {
            return error.UnknownCommand;
        }
    }
}

fn writeCallBack(_: void, str: []const u8) error{}!usize{
    return write(str);
}

pub const Writer = std.io.Writer(void, anyerror, writeCallBack);

pub fn format(comptime fmt: []const u8, args: anytype) void {
    std.fmt.format(Writer{ .context = {} }, fmt, args) catch {};
}

fn ioctl(cmd: usize, arg: usize) isize {
    switch (cmd) {
        termio.TCGETS => {
            var ptr = @intToPtr(*termio.Termios, scheduler.runningProcess.pd.virtToPhy(arg) orelse return -errno.EFAULT);
            ptr.c_iflag = 0;
            ptr.c_oflag = 0;
            ptr.c_cflag = 48; // CS8, Character Size = 8
            ptr.c_lflag = 0;
            ptr.c_line = 0;
            ptr.c_cc = .{0} ** termio.NCCS;
            ptr.c_ispeed = 0;
            ptr.c_ospeed = 0;
            return 0;
        },
        termio.TCSETS => {
            var ptr = @intToPtr(*termio.Termios, scheduler.runningProcess.pd.virtToPhy(arg) orelse return -errno.EFAULT);
            serial.format("New termios={s}\n", .{ ptr });
            return 0;
        },
        else => return -ENOIOCTLCMD,
    }
}

fn poll() Status {
    return .{
        .readable = bufferIn.readableLength() != 0,
        .writable = true,
    };
}