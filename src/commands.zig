const vga = @import("vga.zig");
const std = @import("std");

const TokenIterator = std.mem.TokenIterator;

/// Args only lives for the duration of the function call
pub const CommandFn = fn (args: *TokenIterator) u8;
pub const Command = struct { name: []const u8, cmd: CommandFn };

pub const commands: [1]Command = .{.{ .name = "echo", .cmd = echo }};

fn echo(args: *TokenIterator) u8 {
    while (args.next()) |arg|
        vga.putStr(arg);
    vga.putChar('\n');
    return 0;
}

pub fn find(name: []const u8) ?CommandFn {
    for (commands) |cmd| {
        if (std.mem.eql(u8, name, cmd.name)) {
            return cmd.cmd;
        }
    }
    return null;
}
