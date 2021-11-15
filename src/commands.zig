const vga = @import("vga.zig");
const std = @import("std");
const utils = @import("utils.zig");

const TokenIterator = std.mem.TokenIterator;

/// Args only lives for the duration of the function call
pub const CommandFn = fn (args: *TokenIterator) u8;
pub const Command = struct { name: []const u8, cmd: CommandFn };
extern const stack_top: usize;

pub const commands: [2]Command = .{
    .{ .name = "echo", .cmd = echo },
    .{ .name = "pstack", .cmd = printStack },
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

fn printStack(args: *TokenIterator) u8 {
    vga.format("{x}\n", .{utils.get_register(.esp)});
    vga.format("{x}\n", .{@ptrToInt(&stack_top)});
    return 0;
}
