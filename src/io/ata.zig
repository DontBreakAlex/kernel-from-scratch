const std = @import("std");
const utils = @import("../utils.zig");
const serial = @import("../serial.zig");
const ext = @import("ext2.zig");
const cache = @import("cache.zig");

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

pub const AtaDevice = struct {
    primary: bool,
    slave: bool,

    fn getIoPort(self: AtaDevice, offset: u8) u16 {
        return (if (self.primary) PRIMARY_IO_BASE else SECONDARY_IO_BASE) + offset;
    }

    fn getSelector(self: AtaDevice) u8 {
        return if (self.slave) SELECT_SLAVE else SELECT_MASTER;
    }

    pub fn readStatus(self: AtaDevice) AtaSatus {
        var data: AtaSatus = undefined;
        std.mem.asBytes(&data)[0] = utils.in(u8, self.getIoPort(STATUS_REG_OFFSET));
        return data;
    }

    pub fn select(self: AtaDevice) AtaSatus {
        var data: AtaSatus = undefined;
        utils.out(self.getIoPort(DRIVE_REG_OFFSET), self.getSelector());
        var i: usize = 0;
        while (i < 15) : (i += 1)
            std.mem.asBytes(&data)[0] = utils.in(u8, self.getIoPort(STATUS_REG_OFFSET));
        return data;
    }

    pub fn read(self: AtaDevice, dst: []u8, offset: u28) void {
        std.debug.assert(dst.len % 512 == 0);
        std.debug.assert(dst.len / 512 + 1 < 256);
        const drive = self.getSelector() | ENABLE_LBA | @truncate(u8, offset >> 24);
        const lba_high = @truncate(u8, offset >> 16);
        const lba_mid = @truncate(u8, offset >> 8);
        const lba_low = @truncate(u8, offset);
        const count: u8 = @intCast(u8, dst.len / 512);

        utils.out(self.getIoPort(DRIVE_REG_OFFSET), drive);
        utils.out(self.getIoPort(SEC_CNT_REG_OFFSET), count);
        utils.out(self.getIoPort(LBA_LOW_OFFSET), lba_low);
        utils.out(self.getIoPort(LBA_MID_OFFSET), lba_mid);
        utils.out(self.getIoPort(LBA_HIGH_OFFSET), lba_high);
        utils.out(self.getIoPort(CMD_REG_OFFSET), CMD_READ);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            var status = self.readStatus();
            while (status.bsy == 1 or status.drq == 0)
                status = self.readStatus();
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
};

var disk1 = AtaDevice{
    .primary = true,
    .slave = false,
};
var disk2 = AtaDevice{
    .primary = false,
    .slave = false,
};
var disk3 = AtaDevice{
    .primary = true,
    .slave = true,
};
var disk4 = AtaDevice{
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

    _ = disk3.select();
    // var data: [1024]u8 = .{0} ** 1024;
    // disk3.read(&data, 2);
    // serial.format("{s}\n", .{std.mem.bytesAsValue(ext.Ext2Header, data[0..120])});
    var fs = ext.create(&disk3) catch unreachable;
    var inode = fs.readInode(2) catch unreachable;
    serial.format("{s}\n", .{ inode });
    inode.readDir() catch unreachable;
    // fs.readInode(3) catch unreachable;
}

pub fn init() !void {
    try cache.init();
}
