const std = @import("std");
const utils = @import("../utils.zig");
const serial = @import("../serial.zig");
const ext = @import("ext2.zig");
const cache = @import("cache.zig");
const log = @import("../log.zig");

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
const CMD_WRITE: u8 = 0x30;
const CMD_FLUSH: u8 = 0xE7;

const AtaStatus = packed struct {
    err: u1,
    idx: u1,
    corr: u1,
    drq: u1,
    srv: u1,
    df: u1,
    rdy: u1,
    bsy: u1,
};

pub const AtaDevice = struct {
    primary: bool,
    slave: bool,

    fn getIoPort(self: AtaDevice, offset: u8) u16 {
        return (if (self.primary) PRIMARY_IO_BASE else SECONDARY_IO_BASE) + offset;
    }

    fn getSelector(self: AtaDevice) u8 {
        return if (self.slave) SELECT_SLAVE else SELECT_MASTER;
    }

    pub fn readStatus(self: AtaDevice) AtaStatus {
        var data: AtaStatus = undefined;
        std.mem.asBytes(&data)[0] = utils.in(u8, self.getIoPort(STATUS_REG_OFFSET));
        return data;
    }

    pub fn select(self: AtaDevice) AtaStatus {
        var data: AtaStatus = undefined;
        utils.out(self.getIoPort(DRIVE_REG_OFFSET), self.getSelector());
        var i: usize = 0;
        while (i < 15) : (i += 1)
            std.mem.asBytes(&data)[0] = utils.in(u8, self.getIoPort(STATUS_REG_OFFSET));
        return data;
    }

    pub fn read(self: AtaDevice, dst: []u8, offset: u28) !void {
        std.debug.assert(dst.len % 512 == 0);
        std.debug.assert(dst.len / 512 + 1 < 256);
        const drive = self.getSelector() | ENABLE_LBA | @truncate(u8, offset >> 24);
        const lba_high = @truncate(u8, offset >> 16);
        const lba_mid = @truncate(u8, offset >> 8);
        const lba_low = @truncate(u8, offset);
        const count: u8 = @intCast(u8, dst.len / 512);

        _ = try self.wait_ready();
        utils.out(self.getIoPort(DRIVE_REG_OFFSET), drive);
        utils.out(self.getIoPort(SEC_CNT_REG_OFFSET), count);
        utils.out(self.getIoPort(LBA_LOW_OFFSET), lba_low);
        utils.out(self.getIoPort(LBA_MID_OFFSET), lba_mid);
        utils.out(self.getIoPort(LBA_HIGH_OFFSET), lba_high);
        utils.out(self.getIoPort(CMD_REG_OFFSET), CMD_READ);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            _ = try self.io_wait();
            // TODO: Check for errors
            var j: usize = 0;
            while (j < 256) : (j += 1) {
                var data: u16 = utils.in(u16, self.getIoPort(DATA_REG_OFFSET));
                var index: usize = i * 512 + j * 2;
                dst[index] = @truncate(u8, data);
                dst[index + 1] = @truncate(u8, data >> 8);
            }
        }
    }

    pub fn write(self: AtaDevice, src: []u8, offset: u28) !void {
        log.format("Writting buffer at offset {}...\n", .{offset});
        std.debug.assert(src.len % 512 == 0);
        std.debug.assert(src.len / 512 + 1 < 256);
        const drive = self.getSelector() | ENABLE_LBA | @truncate(u8, offset >> 24);
        const lba_high = @truncate(u8, offset >> 16);
        const lba_mid = @truncate(u8, offset >> 8);
        const lba_low = @truncate(u8, offset);
        const count: u8 = @intCast(u8, src.len / 512);

        _ = try self.wait_ready();
        log.format("Ready\n", .{});
        utils.out(self.getIoPort(DRIVE_REG_OFFSET), drive);
        utils.out(self.getIoPort(SEC_CNT_REG_OFFSET), count);
        utils.out(self.getIoPort(LBA_LOW_OFFSET), lba_low);
        utils.out(self.getIoPort(LBA_MID_OFFSET), lba_mid);
        utils.out(self.getIoPort(LBA_HIGH_OFFSET), lba_high);
        utils.out(self.getIoPort(CMD_REG_OFFSET), CMD_WRITE);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            _ = try self.io_wait();
            // TODO: Check for errors
            var j: usize = 0;
            while (j < 256) : (j += 1) {
                var index: usize = i * 512 + j * 2;
                var data: u16 = @as(u16, src[index + 1]) << 8 | src[index];
                utils.out(self.getIoPort(DATA_REG_OFFSET), data);
            }
        }

        utils.out(self.getIoPort(CMD_REG_OFFSET), CMD_FLUSH);
        log.format("Done !\n", .{});
    }

    fn io_wait(self: AtaDevice) !AtaStatus {
        while (true) {
            const status = self.readStatus();

            if (status.bsy == 0 and status.drq == 1) {
                return status;
            }

            if (status.err == 1 or status.df == 1) {
                return error.DriveError;
            }
        }
    }

    fn wait_ready(self: AtaDevice) !AtaStatus {
        while (true) {
            // TODO: Timeout
            const status = self.readStatus();
            if (status.bsy == 1)
                continue;

            if (status.rdy == 1) {
                return status;
            }

            if (status.err == 1 or status.df == 1) {
                return error.DriveError;
            }
        }
    }
};

pub var disk1 = AtaDevice{
    .primary = true,
    .slave = false,
};
pub var disk2 = AtaDevice{
    .primary = false,
    .slave = false,
};
pub var disk3 = AtaDevice{
    .primary = true,
    .slave = true,
};
pub var disk4 = AtaDevice{
    .primary = false,
    .slave = true,
};

pub fn detectDisks() void {
    serial.format("Primary bus (master)  : {s}\n", .{disk1.select()});
    serial.format("Secondary bus (master): {s}\n", .{disk2.select()});
    utils.out(PRIMARY_CONTROL_BASE, DISABLE_IRQ);
    utils.out(SECONDARY_CONTROL_BASE, DISABLE_IRQ);
    serial.format("Primary bus (slave)   : {s}\n", .{disk3.select()});
    serial.format("Secondary bus (slave) : {s}\n", .{disk4.select()});
    utils.out(PRIMARY_CONTROL_BASE, DISABLE_IRQ);
    utils.out(SECONDARY_CONTROL_BASE, DISABLE_IRQ);
}

pub fn init() !void {
    try cache.init();
}
