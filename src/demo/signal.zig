const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");

fn handleSignal() void {
    vga.putStr("Recieved signal\n");
}

pub fn testSignal() void {
    const pid = lib.fork();
    if (pid == 0) {
        // Child
        _ = lib.signal(.SIGINT, handleSignal);
        lib.exit();
    }
    // Parent
    vga.format("Child has PID {}\n", .{pid});
}
