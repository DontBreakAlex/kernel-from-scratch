pub noinline fn open(buff: usize, size: usize, flags: usize, raw_mode: u16) isize {
    var path = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    var dentry: *dirent.DirEnt= undefined;
    var result = scheduler.runningProcess.cwd.resolve(path, &dentry) catch return -1;
    _ = result;
    // if (result == .ParentExists and )
    const fd = scheduler.runningProcess.getAvailableFd() catch return -1;
    var file: *fs.File = switch (dentry.e_type) {
        .Directory => if (flags & fs.DIRECTORY == 0) return -1 else fs.File.create(dentry, @intCast(u8, flags)) catch return -1,
        .Regular => fs.File.create(dentry, @intCast(u8, flags)) catch return -1,
        else => return -1,
    };
    scheduler.runningProcess.fd[fd] = file;
    return @intCast(isize, fd);
}