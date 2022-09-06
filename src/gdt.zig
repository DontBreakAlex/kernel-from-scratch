// For now this file only contains constants. For the GDT code, see loader.s

pub const KERN_CODE = 0x08;
pub const KERN_DATA = 0x10;
pub const USER_CODE = 0x18;
pub const USER_DATA = 0x20;
pub const TSS_SEG = 0x28;
pub const TLS_SEG = 0x30;

pub const GDTEntry = packed struct {
    limit_low: u16,
    base_low: u24,
    accessed: u1,
    read_write: u1,
    conforming_expand_down: u1,
    code: u1,
    code_data_segment: u1,
    DPL: u2,
    present: u1,
    limit_high: u4,
    available: u1,
    long_mode: u1,
    big: u1,
    gran: u1,
    base_high: u8,
};

extern const gdt_start: GDTEntry;

pub fn getGDTEntry(offset: usize) *GDTEntry {
    return @intToPtr(*GDTEntry, @ptrToInt(&gdt_start) + offset);
}
