const vga = @import("vga.zig");
const kbr = @import("keyboard.zig");
const std = @import("std");
const commands = @import("commands.zig");
const utl = @import("utils.zig");
const mem = @import("memory/mem.zig");
const lib = @import("syslib.zig");

const ArrayList = std.ArrayList;

extern const kend: u8;
extern const kbegin: u8;
const motd = "Welcome to kernel-o-tron ! (0x{x:0>8}-0x{x:0>8})\n";

pub fn run() void {
    lib.tty.clear();
    lib.tty.format(motd, .{ @ptrToInt(&kbegin), @ptrToInt(&kend) });

    while (true) {
        _ = lib.write(1, ">");
        if (readLine()) |line| {
            var args = std.mem.tokenize(u8, line.items, " ");
            if (commands.find(args.next() orelse continue)) |command| {
                _ = command(&args);
            } else {
                lib.tty.format("Command not found: {s}\n", .{line.items});
            }
            line.deinit();
        } else |err| {
            lib.tty.format("\nReadline error: \"{s}\"\n", .{err});
        }
    }
}

pub fn readLine() !ArrayList(u8) {
    var line: ArrayList(u8) = ArrayList(u8).init(lib.userAllocator);
    errdefer line.deinit();
    var n: usize = 0;

    while (true) {
        var key: kbr.KeyPress = undefined;
        _ = lib.read(0, std.mem.asBytes(&key), 1);
        switch (key.key) {
            .BACKSPACE => if (n != 0 and n == line.items.len) {
                lib.tty.erase();
                n -= 1;
                _ = line.pop();
            },
            .LEFT_ARROW => if (n != 0) {
                n -= 1;
                lib.tty.backward();
            },
            .RIGHT_ARROW => if (n < line.items.len) {
                n += 1;
                lib.tty.forward();
            },
            else => if (key.toAscii()) |char| {
                if (char == '\n') {
                    _ = lib.write(1, "\n");
                    return line;
                }
                if (n == line.items.len) {
                    try line.append(char);
                    n += 1;
                    vga.putChar(char);
                } else {
                    try line.insert(n, char);
                    _ = lib.write(1, "\x1b[s");
                    vga.putStr(line.items[n..line.items.len]);
                    // lib.tty.forward();
                    _ = lib.write(1, "\x1b[u");
                    n += 1;
                }
            },
        }
    }

    return line;
}
