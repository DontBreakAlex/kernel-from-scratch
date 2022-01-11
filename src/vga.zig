const std = @import("std");
const utils = @import("utils.zig");
const kbr = @import("keyboard.zig");

const Cursor = @import("cursor.zig").Cursor;

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

const VgaBuffer = struct {
    buffer: [VGA_SIZE]VgaEntry,
    cursor: Cursor,
};

pub const VGA_WIDTH = 80;
pub const VGA_HEIGHT = 25;
const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;

const VGA_BUFFER = @intToPtr([*]volatile VgaEntry, 0xB8000);
pub var CURSOR = Cursor{ .x = 0, .y = 0 };

var VGA_SAVED: [4]VgaBuffer = undefined;
var CURRENT_BUFFER: usize = 0;

var TEXT_COLOR = vgaEntryColor(VgaColor.LIGHT_GREY, VgaColor.BLACK);
var CURRENT_COLOR = VgaColor.BLACK;

inline fn vgaEntryColor(foreground: VgaColor, background: VgaColor) VgaEntryColor {
    return @enumToInt(foreground) | @enumToInt(background) << 4;
}

inline fn vgaEntry(character: u8, color: VgaEntryColor) VgaEntry {
    return @intCast(u16, character) | @intCast(u16, color) << 8;
}

pub fn init() void {
    for (VGA_SAVED) |*saved| {
        var i: usize = 0;
        while (i < VGA_SIZE) : (i += 1) {
            saved.buffer[i] = vgaEntry(' ', TEXT_COLOR);
        }
        saved.cursor = Cursor{ .x = 0, .y = 0 };
    }
    Cursor.enable();
    clear();
}

pub fn clear() void {
    var i: usize = 0;
    while (i < VGA_SIZE) : (i += 1) {
        VGA_BUFFER[i] = vgaEntry(' ', TEXT_COLOR);
    }
    CURSOR.move(0, 0);
}

pub fn erase() void {
    CURSOR.backward();
    VGA_BUFFER[CURSOR.index()] = vgaEntry(' ', TEXT_COLOR);
}

pub fn shiftVga() void {
    var i: usize = VGA_WIDTH;
    while (i < VGA_SIZE) : (i += 1) {
        VGA_BUFFER[i - VGA_WIDTH] = VGA_BUFFER[i];
    }
    i = VGA_SIZE - VGA_WIDTH;
    while (i < VGA_SIZE) : (i += 1) {
        VGA_BUFFER[i] = vgaEntry(' ', TEXT_COLOR);
    }
}

fn swapBuffer(new: usize) void {
    var i: usize = 0;
    while (i < VGA_SIZE) : (i += 1) {
        VGA_SAVED[CURRENT_BUFFER].buffer[i] = VGA_BUFFER[i];
        VGA_BUFFER[i] = VGA_SAVED[new].buffer[i];
    }
    VGA_SAVED[CURRENT_BUFFER].cursor = CURSOR;
    CURSOR = VGA_SAVED[new].cursor;
    CURRENT_BUFFER = new;
    CURSOR.update();
}

pub fn putChar(char: u8) void {
    if (char == '\n') {
        CURSOR.newline();
    } else {
        const index = CURSOR.index();
        VGA_BUFFER[index] = vgaEntry(char, TEXT_COLOR);
        CURSOR.forward();
    }
}

pub fn putStr(data: []const u8) void {
    for (data) |c|
        putChar(c);
}

const VgaError = error{};
fn writeCallBack(_: void, str: []const u8) VgaError!usize {
    putStr(str);
    return str.len;
}

pub const Writer = std.io.Writer(void, VgaError, writeCallBack);

pub fn format(comptime fmt: []const u8, args: anytype) void {
    std.fmt.format(Writer{ .context = {} }, fmt, args) catch {};
}

pub fn putPtr(args: usize) void {
    format("0x{x:0>8}\n", .{args});
}
