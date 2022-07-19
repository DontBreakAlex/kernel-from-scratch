const std = @import("std");
const mem = @import("../../memory/mem.zig");
const DirEnt = @import("../dirent.zig").DirEnt;

const Key = struct {
    parent: *DirEnt,
    name: []const u8,
};
const KeyContext = struct {
    const Wyhash = std.hash.Wyhash;

    pub fn hash(self: @This(), k: Key) u64 {
        _ = self;
        var hasher = Wyhash.init(0);
        @call(.{ .modifier = .always_inline }, hasher.update, .{std.mem.asBytes(&k.parent)});
        @call(.{ .modifier = .always_inline }, hasher.update, .{k.name});
        return hasher.final();
    }
    pub fn eql(self: @This(), a: Key, b: Key) bool {
        _ = self;
        return a.parent == b.parent and std.mem.eql(u8, a.name, b.name);
    }
};
const DirentMap = std.HashMap(Key, *DirEnt, KeyContext, std.hash_map.default_max_load_percentage);
pub var dirents = DirentMap.init(mem.allocator);

const UnusedList = std.TailQueue(void);
pub const UnusedNode = UnusedList.Node;
pub var unusedDirents = UnusedList{};
