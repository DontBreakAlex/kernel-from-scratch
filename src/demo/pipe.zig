const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");
const utils = @import("../utils.zig");

pub noinline fn testPipe() void {
    var pipe = [2]usize{ 0, 0 };
    _ = lib.pipe(pipe);
    const pid = lib.fork();
    if (pid == 0) {
        // Child
        vga.putStr("Hello from child\n");
        _ = lib.write(pipe[1], &.{ 1, 2, 3 }, 3);
        lib.exit(0);
    }
    // Parent
    vga.format("Child has PID {}\n", .{pid});
    var data: [3]u8 = .{ 0, 0, 0 };
    _ = lib.read(pipe[0], &data, 3);
    _ = lib.wait();
    vga.putStr("Child terminated\n");
    vga.format("Read in pipe: {any}\n", .{data});
}
