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
    if (pid == -1)
        return vga.putStr("Fork failure\n");
    if (pid == 0) {
        // Child
        _ = lib.signal(.SIGINT, handleSignal);
        vga.putStr("Hello from child\n");
        while (keepRunning)
            if (lib.sigwait() != 0)
                return vga.putStr("Sigwait failure\n");
        lib.exit(0);
    }
    // Parent
    vga.format("Child has PID {}\n", .{pid});
    var key: u8 = 0;
    vga.putStr("Press key to kill child\n");
    if (lib.read(0, std.mem.asBytes(&key), 1) != 1)
        return vga.putStr("Read failure\n");
    if (lib.kill(@intCast(usize, pid), .SIGINT) != 0)
        return vga.putStr("Kill failure\n");
    if (lib.wait() != pid)
        return vga.putStr("Wait failure\n");
    vga.putStr("Child terminated\n");
}
