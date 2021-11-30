const vga = @import("vga.zig");
const kbr = @import("keyboard.zig");
const std = @import("std");
const commands = @import("commands.zig");
const utl = @import("utils.zig");
const mem = @import("memory.zig");

const ArrayList = std.ArrayList;

extern const kend: u8;
extern const kbegin: u8;
const motd = "Welcome to kernel-from-scratch ! (0x{x:0>8}-0x{x:0>8})\n";

pub fn run() void {
    vga.clear();
    vga.format(motd, .{ @ptrToInt(&kbegin), @ptrToInt(&kend) });

    while (true) {
        vga.putChar('>');
        if (readLine()) |line| {
            defer line.deinit();

            var args = std.mem.tokenize(u8, line.items, " ");
            if (commands.find(args.next() orelse continue)) |command| {
                _ = command(&args);
            } else {
                vga.format("Command not found: {s}\n", .{line.items});
            }
        } else |err| {
            vga.format("\nReadline error: \"{s}\"\n", .{err});
        }
    }
}

pub fn readLine() !ArrayList(u8) {
    var line: ArrayList(u8) = ArrayList(u8).init(mem.phyAllocator);
    errdefer line.deinit();
    var n: usize = 0;

    while (true) {
        const key: kbr.KeyPress = kbr.wait_key();
        switch (key.key) {
            .BACKSPACE => if (n != 0 and n == line.items.len) {
                vga.erase();
                n -= 1;
                _ = line.pop();
            },
            .LEFT_ARROW => if (n != 0) {
                n -= 1;
                vga.CURSOR.backward();
            },
            .RIGHT_ARROW => if (n < line.items.len) {
                n += 1;
                vga.CURSOR.forward();
            },
            else => if (key.toAscii()) |char| {
                if (char == '\n') {
                    vga.CURSOR.newline();
                    return line;
                }
                if (n == line.items.len) {
                    try line.append(char);
                    n += 1;
                    vga.putChar(char);
                } else {
                    try line.insert(n, char);
                    var cursor = vga.CURSOR;
                    vga.putStr(line.items[n..line.items.len]);
                    cursor.forward();
                    vga.CURSOR = cursor;
                    n += 1;
                }
            },
        }
    }

    return line;
}
