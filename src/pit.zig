const utils = @import("utils.zig");
const pic = @import("pic.zig");
const idt = @import("idt.zig");
const vga = @import("vga.zig");

const PIT_CMD_PORT: u8 = 0x43;
const PIT_DATA_PORT: u8 = 0x40;
/// Base PIT frequency (in Hz)
const BASE_FREQ = 1193182;
/// Current divisor
var DIVISOR: u16 = 0xFFFF;

pub fn init() void {
    utils.disable_int();
    idt.setInterruptHandler(pic.PIC1_OFFSET, handleIrq0, true, false);

    // 00  Channel 0
    // 11  Access mode: lobyte/hibyte
    // 010 Operating mode 3
    // 0   Binary mode
    utils.out(PIT_CMD_PORT, @as(u8, 0b00110100));
    utils.out(PIT_DATA_PORT, @as(u8, 0xFF));
    utils.out(PIT_DATA_PORT, @as(u8, 0xFF));
    pic.unMask(0x00);
    utils.enable_int();
}

pub fn setDivisor(divisor: u16) void {
    utils.disable_int();
    utils.out(PIT_CMD_PORT, 0b00110100);
    utils.out(PIT_DATA_PORT, @truncate(u8, divisor));
    utils.out(PIT_DATA_PORT, @truncate(u8, divisor >> 8));
    DIVISOR = divisor;
    utils.enable_int();
}

pub fn setFrequency(frequency: usize) void {
    setDivisor(BASE_FREQ / frequency);
}

/// Number of ticks since kernel started
var ticksSinceBoot: usize = 0;

pub fn handleIrq0() void {
    ticksSinceBoot += 1;
    showUptime();
    utils.out(pic.MASTER_CMD, pic.EOI);
}

fn showUptime() void {
    var seconds = ticksSinceBoot / (BASE_FREQ / @as(usize, DIVISOR));
    var hours = seconds / 60;
    seconds %= 60;
    var days = hours / 24;
    hours %= 24;
    const bck = vga.CURSOR.save();
    vga.CURSOR.goto(vga.VGA_WIDTH - 8, 0);
    vga.format("{d:0>2}:{d:0>2}:{d:0>2}", .{ days, hours, seconds });
    vga.CURSOR = bck;
    vga.CURSOR.restore(bck);
}
