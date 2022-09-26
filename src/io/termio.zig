pub const TCGETS = 0x5401;
pub const TCSETS = 0x5402;

pub const NCCS = 19;

pub const Termios = extern struct {
    /// input mode flags
    c_iflag: u32,
    /// output mode flags
    c_oflag: u32,
    /// control mode flags
    c_cflag: u32,
    /// local mode flags
    c_lflag: u32,
    /// line discipline
    c_line: u8,
    /// control characters
    c_cc: [NCCS]u8,
    /// input speed
    c_ispeed: u32,
    /// output speed
    c_ospeed: u32,
};
