const vga = @import("vga.zig");
const std = @import("std");
const utils = @import("utils.zig");
const lib = @import("syslib.zig");

const ArgsIterator = *std.mem.TokenIterator(u8);

pub const CommandFn = fn (args: ArgsIterator) u8;
pub const Command = struct { name: []const u8, cmd: CommandFn };
extern const stack_top: u8;

pub const commands: [12]Command = .{
    .{ .name = "echo", .cmd = echo },
    .{ .name = "pstack", .cmd = printStack },
    .{ .name = "ptrace", .cmd = printTrace },
    .{ .name = "reboot", .cmd = reboot },
    .{ .name = "halt", .cmd = halt },
    .{ .name = "poweroff", .cmd = poweroff },
    .{ .name = "pmultiboot", .cmd = pmultiboot },
    .{ .name = "int", .cmd = interrupt },
    .{ .name = "panic", .cmd = panic },
    .{ .name = "getpid", .cmd = getPid },
    .{ .name = "test", .cmd = runTest },
    .{ .name = "free", .cmd = free },
};

pub fn find(name: []const u8) ?CommandFn {
    for (commands) |cmd| {
        if (std.mem.eql(u8, name, cmd.name)) {
            return cmd.cmd;
        }
    }
    return null;
}

fn echo(args: ArgsIterator) u8 {
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

fn printStack(_: ArgsIterator) u8 {
    const bottom: usize = utils.get_register(.esp);
    const top: *const u8 = &stack_top;
    const len = (@ptrToInt(top) - bottom);
    const s = @intToPtr([*]u8, bottom)[0..len];
    var i = len - 1;
    var line: [16]u8 = undefined;
    while (i >= 16) : (i -= 16) {
        for (s[i - 15 .. i + 1]) |c, p| {
            line[p] = escaped(c);
        }
        vga.format("{x:0>8}  {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2}  {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2}  |{s}|\n", .{ @ptrToInt(&s[i]), s[i - 15], s[i - 14], s[i - 13], s[i - 12], s[i - 11], s[i - 10], s[i - 9], s[i - 8], s[i - 7], s[i - 6], s[i - 5], s[i - 4], s[i - 3], s[i - 2], s[i - 1], s[i], line });
    }
    if (i != 0) {
        vga.format("{x:0>8}  ", .{@ptrToInt(&s[i])});
        var o = i;
        while (i - o < 8) {
            vga.format("{x:0>2} ", .{s[o]});
            if (o == 0) break;
            o -= 1;
        }
        if (o != 0) {
            vga.putChar(' ');
            while (o != 0) : (o -= 1) {
                vga.format("{x:0>2} ", .{s[o]});
            }
        }
        vga.putChar('\n');
    }
    return 0;
}

fn printTrace(_: ArgsIterator) u8 {
    utils.printTrace();
    return 0;
}

fn reboot(_: ArgsIterator) u8 {
    utils.out(0xCF9, @as(u8, 6));
    return 0;
}

fn halt(_: ArgsIterator) u8 {
    vga.clear();
    vga.putStr("System halted.");
    asm volatile (
        \\cli
        \\hlt
    );
    return 0;
}

// Only works on emulators
fn poweroff(_: ArgsIterator) u8 {
    utils.out(0xB004, @as(u16, 0x2000));
    utils.out(0x604, @as(u16, 0x2000));
    utils.out(0x4004, @as(u16, 0x3400));
    vga.clear();
    asm volatile (
        \\cli
        \\hlt
    );
    return 0;
}

const multiboot = @import("multiboot.zig");
fn pmultiboot(_: ArgsIterator) u8 {
    vga.format("{x}\n", .{(multiboot.MULTIBOOT)});
    return 0;
}

fn interrupt(_: ArgsIterator) u8 {
    asm volatile ("int $1");
    return 0;
}

fn panic(_: ArgsIterator) u8 {
    @panic("User requested panic !");
}

fn getPid(_: ArgsIterator) u8 {
    vga.format("Current PID: {}\n", .{lib.getPid()});
    return 0;
}

fn runTest(args: ArgsIterator) u8 {
    if (args.next()) |arg| {
        if (std.mem.eql(u8, "signal", arg)) {
            @import("demo/signal.zig").testSignal();
            return 0;
        }
        vga.format("No test for: {s}\n", .{arg});
        return 1;
    } else {
        vga.putStr("Error: no tests specified\n");
        return 1;
    }
}

fn free(_: ArgsIterator) u8 {
    var usage: @import("memory/page_allocator.zig").PageAllocator.AllocatorUsage = undefined;
    if (lib.usage(&usage) == -1)
        return 1;
    vga.format("Allocated pages: {}/{}\n", .{ usage.allocated, usage.capacity });
    return 0;
}
