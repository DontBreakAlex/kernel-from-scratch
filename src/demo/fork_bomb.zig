const std = @import("std");
const vga = @import("../vga.zig");
const lib = @import("../syslib.zig");
const utils = @import("../utils.zig");

pub noinline fn bomb() void {
    while (true) {
        const ret = lib.fork();
        switch (ret) {
            -1 => {
                vga.putStr("Fork failure\n");
                if (lib.getPid() == 1)
                    return
                else
                    lib.exit(0);
            },
            0 => {
                vga.format("Hello from PID {}\n", .{lib.getPid()});
            },
            else => {
                const pid = lib.wait();
                vga.format("Child with PID {} died\n", .{pid});
                if (lib.getPid() == 1)
                    return
                else
                    lib.exit(0);
            },
        }
    }
}
