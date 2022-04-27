const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");
const utils = @import("../utils.zig");

pub noinline fn testPipe() void {
    var pipe = [2]isize{ 0, 0 };
    if (lib.pipe(pipe) != 0)
        return vga.putStr("Pipe failure\n");
    const pid = lib.fork();
    if (pid == -1)
        return vga.putStr("Fork failure\n");
    if (pid == 0) {
        // Child
        vga.putStr("Hello from child\n");
        if (lib.write(pipe[1], &.{ 1, 2, 3 }, 3) != 3)
            return vga.putStr("Write failure");
        vga.putStr("Child exiting\n");
        lib.exit(0);
    }
    // Parent
    vga.format("Child has PID {}\n", .{pid});
    var data: [3]u8 = .{ 0, 0, 0 };
    if (lib.read(pipe[0], &data, 3) != 3)
        return vga.putStr("Read failure\n");
    if (lib.wait() != pid)
        return vga.putStr("Wait failure\n");
    vga.putStr("Child terminated\n");
    vga.format("Data read from pipe: {any}\n", .{data});
    if (lib.close(pipe[0]) != 0 or lib.close(pipe[1]) != 0)
        return vga.putStr("Close failure");
}
