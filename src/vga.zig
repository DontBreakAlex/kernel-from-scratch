const std = @import("std");

const VgaEntryColor = u8;
const VgaEntry = u16;

const VgaColor = enum(u8) {
    BLACK = 0,
    BLUE = 1,
    GREEN = 2,
    CYAN = 3,
    RED = 4,
    MAGENTA = 5,
    BROWN = 6,
    LIGHT_GREY = 7,
    DARK_GREY = 8,
    LIGHT_BLUE = 9,
    LIGHT_GREEN = 10,
    LIGHT_CYAN = 11,
    LIGHT_RED = 12,
    LIGHT_MAGENTA = 13,
    LIGHT_BROWN = 14,
    WHITE = 15,
};

const Cursor = struct {
    var x: usize = 0;
    var y: usize = 0;
};

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;

const VGA_BUFFER = @intToPtr([*]volatile VgaEntry, 0xB8000);
const TEXT_COLOR = vgaEntryColor(VgaColor.LIGHT_GREY, VgaColor.BLACK);

inline fn vgaEntryColor(foreground: VgaColor, background: VgaColor) VgaEntryColor {
    return @enumToInt(foreground) | @enumToInt(background) << 4;
}

inline fn vgaEntry(character: u8, color: VgaEntryColor) VgaEntry {
    return @intCast(u16, character) | @intCast(u16, color) << 8;
}

pub fn putChar(char: u8) void {
    if (char == '\n') {
        Cursor.y += 1;
        Cursor.x = 0;
        if (Cursor.y == VGA_HEIGHT) {
            Cursor.y = 0;
        }
    } else {
        const index = Cursor.y * VGA_WIDTH + Cursor.x;
        VGA_BUFFER[index] = vgaEntry(char, TEXT_COLOR);
        Cursor.x += 1;
        if (Cursor.x == VGA_WIDTH) {
            Cursor.x = 0;
            Cursor.y += 1;
            if (Cursor.y == VGA_HEIGHT) {
                Cursor.y = 0;
            }
        }
    }
}

pub fn init() void {
    clear();
}

pub fn clear() void {
    var i: usize = 0;
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 1) {
        VGA_BUFFER[i] = vgaEntry(' ', TEXT_COLOR);
    }
}

pub fn putStr(data: []const u8) void {
    for (data) |c|
        putChar(c);
}

const VgaError = error{};
fn writeCallBack(context: void, str: []const u8) VgaError!usize {
    putStr(str);
    return str.len;
}

const Writer = std.io.Writer(void, VgaError, writeCallBack);

pub fn format(comptime fmt: []const u8, args: anytype) void {
    _ = std.fmt.format(Writer{ .context = {} }, fmt, args) catch void;
}
