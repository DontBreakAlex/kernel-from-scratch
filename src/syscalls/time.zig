const t = @import("../time.zig");

pub noinline fn time(ptr: usize) isize {
    if (ptr != 0)
        return -1;
    return @intCast(isize, t.seconds_since_epoch);
}
