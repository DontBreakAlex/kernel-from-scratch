const std = @import("std");

pub const Format = enum(u4) {
    FIFO = 0x1,
    CharDev = 0x2,
    Directory = 0x4,
    BlkDev = 0x6,
    Regular = 0x8,
    Symlink = 0xA,
    Socket = 0xC,
};

pub const Rights = packed struct {
    read: bool,
    write: bool,
    execute: bool,
};

pub const Mode = packed struct {
    others: Rights,
    group: Rights,
    user: Rights,
    sticky: bool,
    setguid: bool,
    setuid: bool,
    format: Format,

    pub fn toU16(self: *const Mode) u16 {
        const bytes = std.mem.asBytes(self);
        return bytes[0] | @intCast(u16, bytes[1]) << 8;
    }

    pub fn fromU16(raw_mode: u16) Mode {
        return std.mem.bytesToValue(Mode, std.mem.asBytes(&raw_mode));
    }
};

comptime {
    std.debug.assert(@bitSizeOf(Mode) == 16);
}

pub const Type = enum {
    const Self = @This();

    Unknown,
    Regular,
    Directory,
    CharDev,
    Block,
    FIFO,
    Socket,
    Symlink,

    pub fn fromTypeIndicator(indicator: u8) !Type {
        return switch (indicator) {
            0 => .Unknown,
            1 => .Regular,
            2 => .Directory,
            3 => .CharDev,
            4 => .Block,
            5 => .FIFO,
            6 => .Socket,
            7 => .Symlink,
            else => return error.WrongTypeIndicator,
        };
    }

    pub fn toTypeIndicator(self: Self) u8 {
        return switch (self) {
            .Unknown => 0,
            .Regular => 1,
            .Directory => 2,
            .CharDev => 3,
            .Block => 4,
            .FIFO => 5,
            .Socket => 6,
            .Symlink => 7,
        };
    }
};
