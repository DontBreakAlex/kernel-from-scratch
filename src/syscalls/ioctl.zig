const serial = @import("../serial.zig");

pub noinline fn ioctl(fd: usize, cmd: usize, arg: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("ioctl called with fd=0x{x}, cmd=0x{x}, arg=0x{x}", .{ fd, cmd, arg });
    return -38;
}
