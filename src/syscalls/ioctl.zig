const serial = @import("../serial.zig");

pub noinline fn ioctl(fd: usize, cmd: usize, arg: usize) isize {
    serial.format("ioctl called with fd=0x{x}, cmd=0x{x}, arg=0x{x}\n", .{ fd, cmd, arg });
    return -58;
}
