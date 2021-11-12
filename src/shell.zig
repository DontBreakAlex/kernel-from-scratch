const vga = @import("vga.zig");
const kbr = @import("keyboard.zig");
const std = @import("std");
const commands = @import("commands.zig");

const ArrayList = std.ArrayList;

const motd = "Welcome to kernel-from-scratch !\n";

pub fn run() void {
    vga.clear();
    vga.putStr(motd);

    while (true) {
        vga.putChar('>');
        if (readLine()) |line| {
            defer line.deinit();

            var args = std.mem.tokenize(line.items, " ");
            if (commands.find(args.next() orelse unreachable)) |command| {
                _ = command(&args);
            } else {
                vga.format("Command not found: {s}\n", .{line.items});
            }
        } else |err| {
            vga.format("Readline error: \"{s}\"\n", .{err});
        }
    }
}

pub fn readLine() !ArrayList(u8) {
    var line: ArrayList(u8) = ArrayList(u8).init(allocator);
    errdefer line.deinit();

    while (true) {
        const key = kbr.wait_key();
        if (key.toAscii()) |char| {
            vga.putChar(char);
            if (char == '\n')
                return line;
            try line.append(char);
        }
    }

    return line;
}

var buffer: [1000]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
var allocator = &fba.allocator;
