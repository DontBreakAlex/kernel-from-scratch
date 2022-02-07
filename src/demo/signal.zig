const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");
const utils = @import("../utils.zig");

fn handleSignal() void {
    vga.putStr("Recieved signal\n");
    keepRunning = false;
}

var keepRunning: bool = true;

pub noinline fn testSignal() void {
    keepRunning = true;
    const pid = lib.fork();
    if (pid == 0) {
        // Child
        _ = lib.signal(.SIGINT, handleSignal);
        vga.putStr("Hello from child\n");
        while (keepRunning)
            _ = lib.sleep();
        lib.exit(0);
    }
    // Parent
    vga.format("Child has PID {}\n", .{pid});
    // var key: u8 = 0;
    // vga.putStr("Press key to kill child");
    // _ = lib.read(0, std.mem.asBytes(&key), 1);
    _ = lib.kill(@intCast(usize, pid), .SIGINT);
    _ = lib.wait();
    vga.putStr("Child terminated\n");
}
