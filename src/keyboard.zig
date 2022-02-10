const pic = @import("pic.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const kbm = @import("keyboard_map.zig");
const std = @import("std");
const mem = @import("memory/mem.zig");
const serial = @import("serial.zig");
const scheduler = @import("scheduler.zig");
const paging = @import("memory/paging.zig");

pub const Key = kbm.Key;

pub const KeyPress = packed struct {
    key: Key,
    uppercase: bool,

    pub fn toAscii(self: KeyPress) ?u8 {
        return self.key.toAscii(self.uppercase);
    }
};

const KEYBOARD_STATUS: u8 = 0x64;
const KEYBOARD_DATA: u8 = 0x60;

pub var queue: utils.Buffer = utils.Buffer.init();

pub fn init() void {
    idt.setInterruptHandler(pic.PIC1_OFFSET + 1, handleKeyboardInterrupt, .{ .save_fpu = false });

    pic.unMask(0x01);
    vga.putStr("Keyboard initialized\n");
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
    if (key == .LEFT_SHIFT or key == .RIGHT_SHIFT) {
        state.uppercase = !released;
    } else if (released) {
        const key_press = KeyPress{
            .key = key,
            .uppercase = state.uppercase,
        };
        scheduler.writeWithEvent(.{ .SimpleReadable = &queue }, std.mem.asBytes(&key_press)) catch vga.putStr("Could not handle keypress\n");
    }
    if (state.special) state.special = false;
}

var stack: [4096]u8 align(16) = undefined;
const stack_slice = stack[0..];
// https://github.com/ziglang/zig/issues/7286
noinline fn handleKeyboardInterrupt(_: *idt.Regs) void {
    if (utils.get_register(.cr3) == @ptrToInt(paging.kernelPageDirectory.cr3)) {
        readScancode();
    } else {
        @call(.{ .stack = stack_slice }, interuptHelper, .{});
    }
}

fn interuptHelper() void {
    var cr3 = asm volatile (
        \\mov %%cr3, %[ret]
        \\mov %[new_cr3], %%cr3
        : [ret] "=&r" (-> usize),
        : [new_cr3] "r" (paging.kernelPageDirectory.cr3),
    );
    readScancode();
    asm volatile ("mov %[new_cr3], %%cr3"
        :
        : [new_cr3] "r" (cr3),
    );
}

fn readScancode() void {
    const status = utils.in(u8, KEYBOARD_STATUS);
    if (status & 0x1 == 1) {
        handleScancode(utils.in(u8, KEYBOARD_DATA));
    }

    utils.out(pic.MASTER_CMD, pic.EOI);
}
