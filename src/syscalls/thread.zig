const serial = @import("../serial.zig");

pub noinline fn set_thread_area() isize {
    serial.format("set_thread_area called\n", .{});
    return 0;
}