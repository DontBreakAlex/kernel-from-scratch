const vga = @import("vga.zig");
const std = @import("std");
const utils = @import("utils.zig");
const lib = @import("syslib.zig");
const log = @import("log.zig");

const ArgsIterator = *std.mem.TokenIterator(u8);

pub const CommandFn = fn (args: ArgsIterator) u8;
pub const Command = struct { name: []const u8, cmd: CommandFn };
extern const stack_bottom: u8;

pub const commands: [18]Command = .{
    .{ .name = "echo", .cmd = echo },
    // .{ .name = "pstack", .cmd = printStack },
    // .{ .name = "ptrace", .cmd = printTrace },
    .{ .name = "reboot", .cmd = reboot },
    .{ .name = "halt", .cmd = halt },
    .{ .name = "poweroff", .cmd = poweroff },
    .{ .name = "pmultiboot", .cmd = pmultiboot },
    .{ .name = "int", .cmd = interrupt },
    .{ .name = "panic", .cmd = panic },
    .{ .name = "getpid", .cmd = getPid },
    .{ .name = "getuid", .cmd = getUid },
    .{ .name = "test", .cmd = runTest },
    .{ .name = "free", .cmd = free },
    .{ .name = "ps", .cmd = printProcesses },
    .{ .name = "pwd", .cmd = getcwd },
    .{ .name = "cd", .cmd = cd },
    .{ .name = "cat", .cmd = cat },
    .{ .name = "ls", .cmd = ls },
    .{ .name = "write", .cmd = write },
    .{ .name = "exec", .cmd = exec },
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
    const top: usize = utils.get_register(.esp);
    const bottom: *const u8 = &stack_bottom;
    const len = (@ptrToInt(bottom) - top);
    const s = @intToPtr([*]u8, top)[0..len];
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
    log.format("Syncing disks...\n", .{});
    _ = lib.sync();
    log.format("Done !\n", .{});
    utils.out(0xCF9, @as(u8, 6));
    return 0;
}

fn halt(_: ArgsIterator) u8 {
    vga.clear();
    log.format("Syncing disks...\n", .{});
    _ = lib.sync();
    log.format("Done !\n", .{});
    log.format("System halted.\n", .{});
    asm volatile (
        \\cli
        \\hlt
    );
    return 0;
}

// Only works on emulators
pub fn poweroff(_: ArgsIterator) noreturn {
    log.format("Syncing disks...\n", .{});
    _ = lib.sync();
    log.format("Done !\n", .{});
    utils.out(0xB004, @as(u16, 0x2000));
    utils.out(0x604, @as(u16, 0x2000));
    utils.out(0x4004, @as(u16, 0x3400));
    vga.clear();
    asm volatile (
        \\cli
        \\hlt
    );
    unreachable;
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

fn getUid(_: ArgsIterator) u8 {
    vga.format("Current UID: {}\n", .{lib.getUid()});
    return 0;
}

fn runTest(args: ArgsIterator) u8 {
    if (args.next()) |arg| {
        if (std.mem.eql(u8, "signal", arg)) {
            @import("demo/signal.zig").testSignal();
            return 0;
        } else if (std.mem.eql(u8, "pipe", arg)) {
            @import("demo/pipe.zig").testPipe();
            return 0;
        } else if (std.mem.eql(u8, "fork_bomb", arg)) {
            @import("demo/fork_bomb.zig").bomb();
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

fn printProcesses(_: ArgsIterator) u8 {
    return @intCast(u8, lib.command(0));
}

fn getcwd(_: ArgsIterator) u8 {
    var buf: [256]u8 = .{1} ** 256;
    if (lib.getcwd(&buf) < 0) {
        vga.putStr("getcwd failure\n");
        return 1;
    }
    vga.format("{s}\n", .{@ptrCast([*:0]const u8, &buf)});
    return 0;
}

fn cd(args: ArgsIterator) u8 {
    if (args.next()) |directory| {
        if (lib.chdir(directory) < 0) {
            vga.putStr("chdir failed\n");
            return 1;
        }
        return 0;
    }
    vga.putStr("Error: no directory specified\n");
    return 1;
}

fn cat(args: ArgsIterator) u8 {
    if (args.next()) |arg| {
        const fd = lib.open(arg, lib.O_RDONLY, undefined);
        if (fd == -1) {
            vga.putStr("Error: failed to open file\n");
        } else {
            var data: [1024]u8 = undefined;
            var ret = lib.read(fd, &data, 1024);
            while (ret > 0) {
                vga.putStr(data[0..@intCast(usize, ret)]);
                ret = lib.read(fd, &data, 1024);
            }
            _ = lib.close(fd);
            return 0;
        }
    }
    return 1;
}

fn ls(args: ArgsIterator) u8 {
    const path = args.next() orelse ".";
    const fd = lib.open(path, lib.O_DIRECTORY, undefined);
    if (fd < 0) {
        vga.format("Error: failed to open directory {s}\n", .{path});
        return 1;
    }
    defer _ = lib.close(fd);
    var dirs: [8]lib.Dentry = undefined;
    var ret = lib.getdents(fd, &dirs);
    while (ret != 0) {
        if (ret < 0) {
            vga.putStr("Error: getdents failure\n");
            return 1;
        }
        for (dirs[0..@intCast(usize, ret)]) |dir| {
            vga.format("{s}\n", .{dir.name[0..dir.namelen]});
        }
        ret = lib.getdents(fd, &dirs);
    }
    return 0;
}

fn write(args: ArgsIterator) u8 {
    const path = args.next() orelse return 1;
    const data = args.next() orelse return 1;
    const fd = lib.open(path, lib.O_CREAT | lib.O_WRONLY, lib.RegularMode);
    if (fd < 0) {
        vga.format("Error: failed to open file {s}\n", .{path});
        return 1;
    }
    defer _ = lib.close(fd);
    var ret = lib.write(fd, data);
    if (ret != data.len) {
        vga.putStr("Error: write failed\n");
        return 1;
    }
    return 0;
}

fn exec(args: ArgsIterator) u8 {
    const path = args.next() orelse return 1;
    const pid = lib.fork();
    if (pid == -1) {
        lib.putStr("Fork failure\n");
        return 1;
    }
    if (pid == 0) {
        _ = lib.execve(path);
    }
    if (lib.wait() != pid) {
        lib.putStr("Wait failure\n");
        return 1;
    }
    return 0;
}
