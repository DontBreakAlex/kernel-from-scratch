pub const O_SEARCH = O_PATH;
pub const O_EXEC = O_PATH;
pub const O_TTY_INIT = 0;

pub const O_ACCMODE = 03 | O_SEARCH;
pub const O_RDONLY = 00;
pub const O_WRONLY = 01;
pub const O_RDWR = 02;

pub const O_CREAT = 0100;
pub const O_EXCL = 0200;
pub const O_NOCTTY = 0400;
pub const O_TRUNC = 01000;
pub const O_APPEND = 02000;
pub const O_NONBLOCK = 04000;
pub const O_DSYNC = 010000;
pub const O_SYNC = 04010000;
pub const O_RSYNC = 04010000;
pub const O_DIRECTORY = 0200000;
pub const O_NOFOLLOW = 0400000;
pub const O_CLOEXEC = 02000000;

pub const O_ASYNC = 020000;
pub const O_DIRECT = 040000;
pub const O_LARGEFILE = 0100000;
pub const O_NOATIME = 01000000;
pub const O_PATH = 010000000;
pub const O_TMPFILE = 020200000;
