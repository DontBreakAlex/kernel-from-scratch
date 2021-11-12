const vga = @import("vga.zig");
const kbr = @import("keyboard.zig");
const std = @import("std");

const motd = "Welcome to kernel-from-scratch !\n";

pub fn run() void {
    vga.clear();
    vga.moveCursor(0, vga.VGA_HEIGHT - 1);
    vga.putStr(motd);

    while (true) {
        const line = readLine();
        defer line.deinit();
        vga.format("{}\n", line);
    }
}

pub fn readLine() std.ArrayList(u8) {
    const line = std.ArrayList(u8).init(allocator);

    while (true) {
        const key = kbr.wait_key();
        if (key.toAscii()) |char| {
            vga.putChar(char);
            if (key == '\n')
                return line;
            try line.append(char);
        }
    }

    return line;
}

var buffer: [1000]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
var allocator = &fba.allocator;
