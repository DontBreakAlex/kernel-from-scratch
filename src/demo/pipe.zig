const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");
const utils = @import("../utils.zig");

pub noinline fn testPipe() void {
    var pipe = [2]isize{ 0, 0 };
    if (lib.pipe(pipe) != 0)
        return lib.putStr("Pipe failure\n");
    const pid = lib.fork();
    if (pid == -1)
        return lib.putStr("Fork failure\n");
    if (pid == 0) {
        // Child
        lib.putStr("Hello from child\n");
        if (lib.write(pipe[1], &.{ 1, 2, 3 }) != 3)
            return lib.putStr("Write failure");
        lib.putStr("Child exiting\n");
        lib.exit(0);
    }
    // Parent
    lib.tty.format("Child has PID {}\n", .{pid});
    var data: [3]u8 = .{ 0, 0, 0 };
    if (lib.read(pipe[0], &data, 3) != 3)
        return lib.putStr("Read failure\n");
    if (lib.wait() != pid)
        return lib.putStr("Wait failure\n");
    lib.putStr("Child terminated\n");
    lib.tty.format("Data read from pipe: {any}\n", .{data});
    if (lib.close(pipe[0]) != 0 or lib.close(pipe[1]) != 0)
        return lib.putStr("Close failure");
}
