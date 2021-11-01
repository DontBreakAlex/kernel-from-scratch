const std = @import("std");
const utils = @import("utils.zig");
const kbr = @import("keyboard.zig");

// const KeyPress = @import("keyboard_map.zig").KeyPress;

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
    x: usize,
    y: usize,
};

const VgaBuffer = struct {
    buffer: [VGA_SIZE]VgaEntry,
    cursor: Cursor,
};

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;

const VGA_BUFFER = @intToPtr([*]volatile VgaEntry, 0xB8000);
var CURSOR = Cursor{ .x = 0, .y = 0 };

var VGA_SAVED: [4]VgaBuffer = undefined;
var CURRENT_BUFFER: usize = 0;

var TEXT_COLOR = vgaEntryColor(VgaColor.LIGHT_GREY, VgaColor.BLACK);
var CURRENT_COLOR = VgaColor.BLACK;

const CURSOR_CMD = 0x03D4;
const CURSOR_DATA = 0x03D5;

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
    clear();
}

pub fn clear() void {
    var i: usize = 0;
    while (i < VGA_SIZE) : (i += 1) {
        VGA_BUFFER[i] = vgaEntry(' ', TEXT_COLOR);
    }
    CURSOR.x = 0;
    CURSOR.y = 0;
    updateCursor();
}

fn shiftVga() void {
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
    updateCursor();
}

fn updateCursor() void {
    const cursor = CURSOR.x + CURSOR.y * VGA_WIDTH;
    utils.out(CURSOR_CMD, @as(u8, 0x0F));
    utils.out(CURSOR_DATA, @truncate(u8, (cursor & 0xFF)));
    utils.out(CURSOR_CMD, @as(u8, 0x0E));
    utils.out(CURSOR_DATA, @truncate(u8, (cursor >> 8 & 0xFF)));
}

pub fn putChar(char: u8) void {
    if (char == '\n') {
        CURSOR.x = 0;
        if (CURSOR.y + 1 == VGA_HEIGHT) {
            shiftVga();
        } else {
            CURSOR.y += 1;
        }
    } else {
        const index = CURSOR.y * VGA_WIDTH + CURSOR.x;
        VGA_BUFFER[index] = vgaEntry(char, TEXT_COLOR);
        CURSOR.x += 1;
        if (CURSOR.x == VGA_WIDTH) {
            CURSOR.x = 0;
            if (CURSOR.y + 1 == VGA_HEIGHT) {
                shiftVga();
            } else {
                CURSOR.y += 1;
            }
        }
    }
    updateCursor();
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

pub fn readKeys() void {
    while (true) {
        const key: kbr.KeyPress = kbr.wait_key();
        switch (key.key) {
            .LEFT_ARROW => {
                if (CURSOR.x != 0)
                    CURSOR.x -= 1;
                updateCursor();
            },
            .RIGHT_ARROW => {
                if (CURSOR.x != VGA_WIDTH)
                    CURSOR.x += 1;
                updateCursor();
            },
            .PAGE_UP => {
                if (CURRENT_COLOR != .WHITE) {
                    CURRENT_COLOR = @intToEnum(VgaColor, @enumToInt(CURRENT_COLOR) + 1);
                    TEXT_COLOR = vgaEntryColor(VgaColor.LIGHT_GREY, CURRENT_COLOR);
                }
            },
            .PAGE_DOWN => {
                if (CURRENT_COLOR != .BLACK) {
                    CURRENT_COLOR = @intToEnum(VgaColor, @enumToInt(CURRENT_COLOR) - 1);
                    TEXT_COLOR = vgaEntryColor(VgaColor.LIGHT_GREY, CURRENT_COLOR);
                }
            },
            .F1 => swapBuffer(0),
            .F2 => swapBuffer(1),
            .F3 => swapBuffer(2),
            .F4 => swapBuffer(3),
            else => key.print(),
        }
    }
}
