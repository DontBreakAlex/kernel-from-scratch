pub const TCGETS = 0x5401;
pub const TCSETS = 0x5402;
pub const TCSETSW = 0x5403;
pub const TCSETSF = 0x5404;
pub const TCGETA = 0x5405;
pub const TCSETA = 0x5406;
pub const TCSETAW = 0x5407;
pub const TCSETAF = 0x5408;
pub const TCSBRK = 0x5409;
pub const TCXONC = 0x540A;
pub const TCFLSH = 0x540B;
pub const TIOCEXCL = 0x540C;
pub const TIOCNXCL = 0x540D;
pub const TIOCSCTTY = 0x540E;
pub const TIOCGPGRP = 0x540F;
pub const TIOCSPGRP = 0x5410;
pub const TIOCOUTQ = 0x5411;
pub const TIOCSTI = 0x5412;
pub const TIOCGWINSZ = 0x5413;
pub const TIOCSWINSZ = 0x5414;
pub const TIOCMGET = 0x5415;
pub const TIOCMBIS = 0x5416;
pub const TIOCMBIC = 0x5417;
pub const TIOCMSET = 0x5418;
pub const TIOCGSOFTCAR = 0x5419;
pub const TIOCSSOFTCAR = 0x541A;
pub const FIONREAD = 0x541B;

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

pub const Winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};
