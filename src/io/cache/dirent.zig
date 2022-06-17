const std = @import("std");
const mem = @import("../../memory/mem.zig");

const Key = struct {
    parent: *Dentry,
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
        return a.parent == b.parent and std.mem.eql(a.name, b.name);
    }
};
const DirentMap = std.HashMap(Key, *Dentry, KeyContext, std.hash_map.default_max_load_percentage);
pub const dirents = DirEnt.init(mem.allocator);
