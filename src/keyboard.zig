const pic = @import("pic.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const kbm = @import("keyboard_map.zig");
const std = @import("std");

pub const Key = kbm.Key;

pub const KeyPress = struct {
    key: Key,
    uppercase: bool,

    pub fn toAscii(self: KeyPress) ?u8 {
        return self.key.toAscii(self.uppercase);
    }
};

const KEYBOARD_STATUS: u8 = 0x64;
const KEYBOARD_DATA: u8 = 0x60;

var QUEUE: [32]KeyPress = undefined;
var QUEUE_PTR: usize = 0;

pub fn init() void {
    idt.setInterruptHandler(pic.PIC1_OFFSET + 1, readScancode);
    idt.setInterruptHandler(pic.PIC1_OFFSET, handle_irq0);

    pic.unMask(0x01);
    vga.putStr("Keyboard initialized\n");
}

fn handle_irq0() void {
    utils.out(pic.MASTER_CMD, pic.EOI);
    vga.putStr("Got irq0\n");
}

const QueueError = error{
    Full,
    Empty,
};

pub fn pushKey(key: Key, uppercase: bool) QueueError!void {
    if (QUEUE_PTR == 32)
        return QueueError.Full;

    QUEUE_PTR += 1;
    QUEUE[QUEUE_PTR - 1] = KeyPress{
        .key = key,
        .uppercase = uppercase,
    };
}

pub fn popKey() QueueError!KeyPress {
    if (QUEUE_PTR == 0)
        return QueueError.Empty;

    QUEUE_PTR -= 1;
    return QUEUE[QUEUE_PTR];
}

pub fn waitKey() KeyPress {
    while (true) {
        if (popKey()) |key| {
            return key;
        } else |_| {
            asm volatile ("hlt");
        }
    }
}

fn handleScancode(scan_code: u8) void {
    const state = struct {
        var uppercase: bool = false;
        var special: bool = false;
    };
    var released = false;
    if (scan_code == 0xe0) {
        state.special = true;
        return;
    }

    if (scan_code >= 128) released = true;

    const key_code = @truncate(u7, scan_code); // Remove released bit;
    const key: Key = if (state.special) kbm.parseSpecial(key_code) else kbm.map[key_code];
    // vga.format("Scancode: {x}, Keycode: {x}\n", .{ scan_code, key_code });
    if (key == .LEFT_SHIFT or key == .RIGHT_SHIFT) {
        state.uppercase = !released;
    } else if (released) {
        pushKey(key, state.uppercase) catch vga.putStr("Could not handle key: queue is full\n");
    }
    if (state.special) state.special = false;
}

// https://github.com/ziglang/zig/issues/7286
noinline fn readScancode() void {
    const status = utils.in(u8, KEYBOARD_STATUS);
    if (status & 0x1 == 1) {
        handleScancode(utils.in(u8, KEYBOARD_DATA));
    }

    utils.out(pic.MASTER_CMD, pic.EOI);
}
