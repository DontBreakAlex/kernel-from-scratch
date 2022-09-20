const cache = @import("../io/cache.zig");
const serial = @import("../serial.zig");
const fs = @import("../io/fs.zig");

pub noinline fn sync() isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("sync called", .{});
    cache.syncAllBuffers();
    fs.root_fs.sync() catch {};
    return 0;
}
