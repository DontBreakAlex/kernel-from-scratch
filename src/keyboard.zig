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

    pub fn print(self: KeyPress) void {
        kbm.printKey(self.key);
    }
};

const KEYBOARD_STATUS: u8 = 0x64;
const KEYBOARD_DATA: u8 = 0x60;

var QUEUE: [32]KeyPress = undefined;
var QUEUE_PTR: usize = 0;

pub fn init() void {
    idt.setIdtEntry(pic.PIC1_OFFSET, @ptrToInt(handle_irq0));
    idt.setIdtEntry(pic.PIC1_OFFSET + 1, @ptrToInt(handle_keyboard));

    pic.unMask(0x01);
    vga.putStr("Keyboard initialized\n");
}

export fn handle_irq0() callconv(.Naked) void {
    asm volatile ("pusha");
    utils.out(pic.MASTER_CMD, pic.EOI);
    vga.putStr("Got irq0\n");
    asm volatile (
        \\popa
        \\iret
    );
}

const QueueError = error{
    Full,
    Empty,
};

pub fn push_key(key: Key, uppercase: bool) QueueError!void {
    if (QUEUE_PTR == 32)
        return QueueError.Full;

    QUEUE_PTR += 1;
    QUEUE[QUEUE_PTR - 1] = KeyPress{
        .key = key,
        .uppercase = uppercase,
    };
}

pub fn pop_key() QueueError!KeyPress {
    if (QUEUE_PTR == 0)
        return QueueError.Empty;

    QUEUE_PTR -= 1;
    return QUEUE[QUEUE_PTR];
}

pub fn wait_key() KeyPress {
    while (true) {
        if (pop_key()) |key| {
            return key;
        } else |_| {
            asm volatile ("hlt");
        }
    }
}

// https://github.com/ziglang/zig/issues/7286
noinline fn handle_scancode(scan_code: u8) void {
    const state = struct {
        var uppercase: bool = false;
    };
    var released = false;

    if (scan_code >= 128)
        released = true;

    const key_code = @truncate(u7, scan_code); // Remove released bit;
    const key: Key = kbm.map[key_code];
    // vga.format("Scancode: {x}, Keycode: {x}, Key: {}\n", .{ scan_code, key_code, key });
    if (key == .LEFT_SHIFT) {
        state.uppercase = !released;
    } else if (released) {
        push_key(key, state.uppercase) catch |_| vga.putStr("Could not handle key: queue is full\n");
    }
}

export fn handle_keyboard() callconv(.Naked) void {
    // TODO: Save save xmm registers
    asm volatile (
        \\pusha
    );

    const status = utils.in(u8, KEYBOARD_STATUS);
    if (status & 0x1 == 1) {
        handle_scancode(utils.in(u8, KEYBOARD_DATA));
    }

    utils.out(pic.MASTER_CMD, pic.EOI);
    asm volatile (
        \\popa
        \\iret
    );
}
