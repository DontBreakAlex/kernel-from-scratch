const time = @import("../time.zig");
const s = @import("../scheduler.zig");

const Timespec = time.Timespec;

pub const Stat = struct {
    st_dev: u32,
    st_ino: u32,
    st_mode: u16,
    st_nlink: u16,
    st_uid: u16,
    st_gid: u16,
    st_rdev: u16,
    __pad2: u16,
    st_size: u32,
    st_blksize: u32,
    st_blocks: u32,
    st_atim: Timespec,
    st_mtim: Timespec,
    st_ctim: Timespec,
    __unused4: u32,
    __unused5: u32,
};
pub const Stat64 = struct {
    st_dev: u64,
    __pad0: [4]u8,
    __st_ino: u32,
    st_mode: u32,
    st_nlink: u32,
    st_uid: u32,
    st_gid: u32,
    st_rdev: u16,
    __pad3: [10]u8,
    st_size: i64,
    st_blksize: u32,
    st_blocks: u32,
    __pad4: u32,
    st_atim: Timespec,
    st_mtim: Timespec,
    st_ctim: Timespec,
    st_ino: u64,
};

pub noinline fn stat64(ptr: usize, size: usize, statbuf: usize) isize {
    do_stat64(
        s.runningProcess.pd.vBufferToPhy(size, ptr) catch return -1,
        @intToPtr(s.runningProcess.pd.virtToPhy(statbuf)) orelse return -1,
    );
}

fn do_stat64(path: []const u8, statbuf: *Stat64) !void {
    var dentry: *DirEnt = try s.runningProcess.cwd.resolve(path, &dentry);
}
