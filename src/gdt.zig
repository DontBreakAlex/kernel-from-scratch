// For now this file only contains constants. For the GDT code, see loader.s

pub const KERN_CODE = 0x08;
pub const KERN_DATA = 0x10;
pub const USER_CODE = 0x18;
pub const USER_DATA = 0x20;