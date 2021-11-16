const vga = @import("vga.zig");
const std = @import("std");
const utils = @import("utils.zig");

const TokenIterator = std.mem.TokenIterator;

/// Args only lives for the duration of the function call
pub const CommandFn = fn (args: *TokenIterator) u8;
pub const Command = struct { name: []const u8, cmd: CommandFn };
extern const stack_top: u8;

pub const commands: [3]Command = .{
    .{ .name = "echo", .cmd = echo },
    .{ .name = "pstack", .cmd = printStack },
    .{ .name = "panic", .cmd = pan },
};

pub fn find(name: []const u8) ?CommandFn {
    for (commands) |cmd| {
        if (std.mem.eql(u8, name, cmd.name)) {
            return cmd.cmd;
        }
    }
    return null;
}

fn echo(args: *TokenIterator) u8 {
    while (args.next()) |arg|
        vga.putStr(arg);
    vga.putChar('\n');
    return 0;
}

fn escaped(char: u8) u8 {
    if (char >= ' ' and char <= '~')
        return char;
    return '.';
}

fn printStack(args: *TokenIterator) u8 {
    var yolo: [15]u8 = .{'a', 'b', 'c', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p'};
    const bottom: usize = utils.get_register(.esp);
    const top: *const u8 = &stack_top;
    const len = (@ptrToInt(top) - bottom);
    const s = @intToPtr([*]u8, bottom)[0..bottom];
    var i = len - 1;
    var line: [16]u8 = undefined;
    while (i >= 16) : (i -= 16) {
        for (s[i-15..i+1]) |c, p| {
            line[p] = escaped(c);
        }
        vga.format("{x:0>8}  {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2}  {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2}  |{s}|\n", .{
            @ptrToInt(&s[i]), s[i-15], s[i - 14], s[i - 13], s[i - 12], s[i - 11], s[i - 10], s[i - 9], s[i - 8], s[i - 7], s[i - 6], s[i - 5], s[i - 4], s[i - 3], s[i - 2], s[i - 1], s[i], line
        });
    }
    if (i != 0) {
        vga.format("{x:0>8}  ", .{ @ptrToInt(&s[i] )});
        var o = i;
        while (i - o < 8) {
            vga.format("{x:0>2} ", .{ s[o] });
            if (o == 0) break;
            o -= 1;
        }
        if (o != 0) {
            vga.putChar(' ');
            while (o != 0) : (o -= 1) {
                vga.format("{x:0>2} ", .{ s[o] });
            }
        }
        vga.putChar('\n');
    }
    return 0;
}

fn pan(args: *TokenIterator) u8 {
    var i :usize = 0;
    i -= 1;
    return 0;
}