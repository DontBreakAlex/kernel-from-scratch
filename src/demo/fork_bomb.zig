const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");
const utils = @import("../utils.zig");

pub noinline fn bomb() void {
    while (true) {
        switch (lib.fork()) {
            -1 => {
                vga.putStr("Fork failure\n");
                lib.exit(1);
            },
            0 => {
                vga.format("Hello from PID {}\n", .{ lib.getPid() });
            },
            else => {
                _ = lib.wait();
                return;
            },
        }
    }
}
