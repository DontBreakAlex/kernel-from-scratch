const pic = @import("pic.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const kbm = @import("keyboard_map.zig");
const std = @import("std");
const Key = kbm.Key;

extern fn boch_break() void;

const KEYBOARD_STATUS: u8 = 0x64;
const KEYBOARD_DATA: u8 = 0x60;

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

export fn handle_keyboard() callconv(.Naked) void {
    // TODO: Save save xmm registers
    asm volatile (
        \\pusha
    );
    const state = struct {
        var uppercase: bool = false;
    };

    const status = utils.in(u8, KEYBOARD_STATUS);
    if (status & 0x1 == 1) {
        var released = false;
        const scan_code = utils.in(u8, KEYBOARD_DATA);
        if (scan_code >= 128)
            released = true;
        const key_code = @truncate(u7, scan_code); // Remove released bit;
        const key: Key = kbm.map[key_code];
        if (key == .LEFT_SHIFT) {
            state.uppercase = !released;
        } else if (released == false) {
            const ascii = key.toAscii();
            if (ascii) |char| {
                vga.putChar(char);
            } else {
                vga.format("{}", .{key});
            }
        }
    }

    utils.out(pic.MASTER_CMD, pic.EOI);
    asm volatile (
        \\popa
        \\iret
    );
}