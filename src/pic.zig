const utils = @import("utils.zig");
const vga = @import("vga.zig");

pub const MASTER_CMD = 0x20;
pub const MASTER_DATA = 0x21;
pub const SLAVE_CMD = 0xA0;
pub const SLAVE_DATA = 0xA1;

const PIC_INIT: u8 = 0x11;
pub const PIC1_OFFSET: u8 = 0x20;
pub const PIC2_OFFSET: u8 = 0x28;
const IRQ_MAP_FROM_SLAVE: u8 = 0x04;
const IRQ_MAP_TO_MASTER: u8 = 0x02;
const MODE_8086: u8 = 0x01;

pub const EOI: u8 = 0x20;

pub fn init() void {
    // Make PIC wait for the 3 initialization words
    utils.out(MASTER_CMD, PIC_INIT);
    utils.ioWait();
    utils.out(SLAVE_CMD, PIC_INIT);
    utils.ioWait();

    // Set vector offsets (ICW2)
    utils.out(MASTER_DATA, PIC1_OFFSET);
    utils.ioWait();
    utils.out(SLAVE_DATA, PIC2_OFFSET);
    utils.ioWait();

    // Cascading (ICW3)
    utils.out(MASTER_DATA, IRQ_MAP_FROM_SLAVE);
    utils.ioWait();
    utils.out(SLAVE_DATA, IRQ_MAP_TO_MASTER);
    utils.ioWait();

    // Set mode (ICW4)
    utils.out(MASTER_DATA, MODE_8086);
    utils.ioWait();
    utils.out(SLAVE_DATA, MODE_8086);
    utils.ioWait();

    // Mask all IRQ
    utils.out(MASTER_DATA, @as(u8, 0xFF));
    utils.ioWait();
    utils.out(SLAVE_DATA, @as(u8, 0xFF));
    utils.ioWait();

    // Unmask cascading
    // utils.out(MASTER_DATA, @as(u8, 0x02));
    // utils.ioWait();
}

pub fn unMask(irq: u3) void {
    const old_mask = utils.in(u8, MASTER_DATA);
    const tmp_mask = ~(@as(u8, 1) << irq);
    const new_mask = old_mask & tmp_mask;
    vga.format("Old mask: {b}, tmp mask: {b}, new mask: {b}\n", .{ old_mask, tmp_mask, new_mask });
    utils.out(MASTER_DATA, new_mask);
}
