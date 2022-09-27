const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const errno = @import("errno.zig");

const File = @import("../io/fs.zig").File;

pub fn dupfd(fromfd: usize) !usize {
    var fd = try scheduler.runningProcess.getAvailableFd();
    var fromfile: *File = scheduler.runningProcess.fd[fromfd] orelse return error.BadFD;
    scheduler.runningProcess.fd[fd] = fromfile;
    fromfile.dup();
    return fd;
}