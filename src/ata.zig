const std = @import("std");
const utils = @import("utils.zig");
const serial = @import("serial.zig");

const PRIMARY_IO_BASE: u16 = 0x1F0;
const PRIMARY_CONTROL_BASE: u16 = 0x3F6;

const SECONDARY_IO_BASE: u16 = 0x170;
const SECONDARY_CONTROL_BASE: u16 = 0x376;

const DATA_REG_OFFSET = 0;
const ERR_REG_OFFSET = 1;
const FEATURE_REG_OFFSET = 1;
const SEC_CNT_REG_OFFSET = 2;
const LBA_LOW_OFFSET = 3;
const LBA_MID_OFFSET = 4;
const LBA_HIGH_OFFSET = 5;
const DRIVE_REG_OFFSET = 6;
const STATUS_REG_OFFSET = 7;
const CMD_REG_OFFSET = 7;

const SELECT_MASTER: u8 = 0b10100000;
const SELECT_SLAVE: u8 = 0b10110000;
const ENABLE_LBA: u8 = 0b01000000;
const DISABLE_IRQ: u8 = 0b10;

const CMD_READ: u8 = 0x20;

const AtaSatus = packed struct {
    err: u1,
    idx: u1,
    corr: u1,
    drq: u1,
    srv: u1,
    df: u1,
    rdy: u1,
    bsy: u1,
};

pub fn readStatus(io_port: u16) AtaSatus {
    var data: AtaSatus = undefined;
    std.mem.asBytes(&data)[0] = utils.in(u8, io_port + STATUS_REG_OFFSET);
    return data;
}

pub fn select(io_port: u16, drive: u8) AtaSatus {
    var data: AtaSatus = undefined;
    utils.out(io_port + DRIVE_REG_OFFSET, drive);
    var i: usize = 0;
    while (i < 15) : (i += 1)
        std.mem.asBytes(&data)[0] = utils.in(u8, io_port + STATUS_REG_OFFSET);
    return data;
}

pub fn detectDisks() void {
    serial.format("Primary bus (master)  : {s}\n", .{select(PRIMARY_IO_BASE, SELECT_MASTER)});
    serial.format("Secondary bus (master): {s}\n", .{select(SECONDARY_IO_BASE, SELECT_MASTER)});
    serial.format("Primary bus (slave)   : {s}\n", .{select(PRIMARY_IO_BASE, SELECT_SLAVE)});
    serial.format("Secondary bus (slave) : {s}\n", .{select(SECONDARY_IO_BASE, SELECT_SLAVE)});

    _ = select(PRIMARY_IO_BASE, SELECT_SLAVE);
    utils.out(PRIMARY_CONTROL_BASE, DISABLE_IRQ);
    var data: [512]u8 = .{0} ** 512;
    read(&data, PRIMARY_IO_BASE, SELECT_SLAVE, 0);
    serial.format("{s}\n", .{data});
}

pub fn read(dst: []u8, io_port: u16, drv: u8, offset: u28) void {
    std.debug.assert(dst.len % 512 == 0);
    std.debug.assert(dst.len / 512 + 1 < 256);
    const drive = drv | ENABLE_LBA | @truncate(u8, offset >> 24);
    const lba_high = @truncate(u8, offset >> 16);
    const lba_mid = @truncate(u8, offset >> 8);
    const lba_low = @truncate(u8, offset);
    const count: u8 = @intCast(u8, dst.len / 512);

    utils.out(io_port + DRIVE_REG_OFFSET, drive);
    utils.out(io_port + SEC_CNT_REG_OFFSET, count);
    utils.out(io_port + LBA_LOW_OFFSET, lba_low);
    utils.out(io_port + LBA_MID_OFFSET, lba_mid);
    utils.out(io_port + LBA_HIGH_OFFSET, lba_high);
    utils.out(io_port + CMD_REG_OFFSET, CMD_READ);

    var i: usize = 0;
    while (i < count) : (i += 1) {
        var status = readStatus(io_port);
        while (status.bsy == 1 or status.drq == 0)
            status = readStatus(io_port);
        // TODO: Check for errors
        var j: usize = 0;
        while (j < 256) : (j += 1) {
            var data: u16 = utils.in(u16, io_port + DATA_REG_OFFSET);
            var index: usize = i * 512 + j * 2;
            dst[index] = @truncate(u8, data);
            dst[index + 1] = @truncate(u8, data >> 8);
        }
    }
}
