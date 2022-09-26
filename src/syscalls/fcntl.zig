const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");

const Command = enum(usize) { F_DUPFD = 0, F_GETFD = 1, F_SETFD = 2, F_GETFL = 3, F_SETFL = 4, F_GETLK = 5, F_SETLK = 6, F_SETLKW = 7, F_SETOWN = 8, F_GETOWN = 9, F_SETSIG = 10, F_GETSIG = 11, _ };

const FD_CLOEXEC = 1;

pub noinline fn fcntl(fd: usize, cmd: usize, arg: usize) isize {
    var command = @intToEnum(Command, cmd);
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("fnctl called with fd={}, cmd={}, arg={}", .{ fd, command, arg });
    return -38;
}

// fn do_fcntl(fd: usize, cmd: Command, arg: usize) isize {
//     return switch (cmd) {
//         else => -1,
//     };
// }
