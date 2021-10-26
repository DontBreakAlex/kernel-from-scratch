const pic = @import("pic.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const keymap = @import("keyboard_map.zig").keymap;

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

    const status = utils.in(u8, KEYBOARD_STATUS);
    if (status & 0x1 == 1) {
        const keycode = utils.in(u8, KEYBOARD_DATA);
        if (keycode > 0 and keycode < 128) {
            // vga.format("{d}", .{keycode});
            vga.putChar(keymap[keycode]);
        }
    }

    utils.out(pic.MASTER_CMD, pic.EOI);
    asm volatile (
        \\popa
        \\iret
    );
}
