const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");
const utils = @import("../utils.zig");

pub noinline fn bomb() void {
    const pid = lib.fork();
    if (pid == -1) {
        return vga.putStr("Fork failure\n");
    }
    if (pid == 0) {
        var pid2: isize = 0;
        while (true) {
            pid2 = lib.fork();
            if (pid2 == -1) {
                lib.exit(0);
            }
            if (pid != 0)
                vga.format("Hello from PID {}\n", .{ pid2 });
        }
    }
}
