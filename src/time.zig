const utils = @import("utils.zig");
const log = @import("log.zig");

const CMOS_ADDR = 0x70;
const CMOS_DATA = 0x71;

pub const Timespec = extern struct {
    tv_sec: i32,
    tv_nsec: i32,
};

pub var seconds_since_epoch: usize = 0;

fn isCmosUpadating() bool {
    utils.out(CMOS_ADDR, @as(u8, 0x0A));
    return (utils.in(u8, CMOS_DATA) & 0x80) == 0x80;
}

fn readRtc(register: u8) u8 {
    utils.out(CMOS_ADDR, register);
    return utils.in(u8, CMOS_DATA);
}

pub fn readTimeFromRTC() void {
    while (isCmosUpadating()) {}

    var seconds = readRtc(0x00);
    var minutes = readRtc(0x02);
    var hours = readRtc(0x04);
    var days = readRtc(0x07);
    var months = readRtc(0x08);
    var years = readRtc(0x09);

    var last_seconds: u8 = undefined;
    var last_minutes: u8 = undefined;
    var last_hours: u8 = undefined;
    var last_days: u8 = undefined;
    var last_months: u8 = undefined;
    var last_years: u8 = undefined;

    while (true) {
        last_seconds = seconds;
        last_minutes = minutes;
        last_hours = hours;
        last_days = days;
        last_months = months;
        last_years = years;

        seconds = readRtc(0x00);
        minutes = readRtc(0x02);
        hours = readRtc(0x04);
        days = readRtc(0x07);
        months = readRtc(0x08);
        years = readRtc(0x09);

        if (seconds == last_seconds and minutes == last_minutes and hours == last_hours and last_days == days and months == last_months)
            break;
    }
    const isBinary = (readRtc(0x0B) & 0x04) == 0x04;

    if (!isBinary) {
        // The time is encoded in BCD...
        seconds = (seconds & 0x0F) + ((seconds / 16) * 10);
        minutes = (minutes & 0x0F) + ((minutes / 16) * 10);
        hours = ((hours & 0x0F) + (((hours & 0x70) / 16) * 10)) | (hours & 0x80);
        days = (days & 0x0F) + ((days / 16) * 10);
        months = (months & 0x0F) + ((months / 16) * 10);
        years = (years & 0x0F) + ((years / 16) * 10);
    }

    seconds_since_epoch = daysSinceEpoch(2000 + @as(u32, years), months, days) * 86400 + @as(u32, hours) * 3600 + @as(u32, minutes) * 60 + @as(u32, seconds);

    log.format("Current time: 20{:0>2}/{:0>2}/{:0>2} {:0>2}:{:0>2}:{:0>2}\nSeconds since epoch: {}\n", .{ years, months, days, hours, minutes, seconds, seconds_since_epoch });
}

fn daysSinceEpoch(year: u32, month: u32, day: u32) u32 {
    var year_days = (year - 1970) * 365;
    {
        var i: usize = year - 1;
        while (i > 1970) : (i -= 1) {
            if (isLeapYear(i)) {
                year_days += 1;
            }
        }
    }

    var month_days: u32 = 0;
    {
        var i: usize = 0;
        while (i < month) : (i += 1) {
            month_days += switch (i) {
                0, 2, 4, 6, 7, 9, 11 => 31,
                3, 5, 8, 10 => 30,
                1 => if (isLeapYear(year)) @as(u32, 29) else @as(u32, 28),
                else => @as(usize, 0),
            };
        }
    }

    return year_days + month_days + day - 1;
}

fn isLeapYear(year: u32) bool {
    return if (year % 400 == 0)
        true
    else if (year % 100 == 0)
        false
    else
        year % 4 == 0;
}
