/// Operation not permitted
pub const EPERM = 1;
/// No such file or directory
pub const ENOENT = 2;
/// No such process
pub const ESRCH = 3;
/// Interrupted system call
pub const EINTR = 4;
/// I/O error
pub const EIO = 5;
/// No such device or address
pub const ENXIO = 6;
/// Argument list too long
pub const E2BIG = 7;
/// Exec format error
pub const ENOEXEC = 8;
/// Bad file number
pub const EBADF = 9;
/// No child processes
pub const ECHILD = 10;
/// Try again
pub const EAGAIN = 11;
/// Out of memory
pub const ENOMEM = 12;
/// Permission denied
pub const EACCES = 13;
/// Bad address
pub const EFAULT = 14;
/// Block device required
pub const ENOTBLK = 15;
/// Device or resource busy
pub const EBUSY = 16;
/// File exists
pub const EEXIST = 17;
/// Cross-device link
pub const EXDEV = 18;
/// No such device
pub const ENODEV = 19;
/// Not a directory
pub const ENOTDIR = 20;
/// Is a directory
pub const EISDIR = 21;
/// Invalid argument
pub const EINVAL = 22;
/// File table overflow
pub const ENFILE = 23;
/// Too many open files
pub const EMFILE = 24;
/// Not a typewriter
pub const ENOTTY = 25;
/// Text file busy
pub const ETXTBSY = 26;
/// File too large
pub const EFBIG = 27;
/// No space left on device
pub const ENOSPC = 28;
/// Illegal seek
pub const ESPIPE = 29;
/// Read-only file system
pub const EROFS = 30;
/// Too many links
pub const EMLINK = 31;
/// Broken pipe
pub const EPIPE = 32;
/// Math argument out of domain of func
pub const EDOM = 33;
/// Math result not representable
pub const ERANGE = 34;

pub const ENOSYS = 38;

pub const SyscallError = error{
    NotPermitted,
    NoSuchFile,
    NoSuchProcess,
    Interrupted,
    IOError,
    NoSuchIO,
    ArgListTooLong,
    BadExecFormat,
    BadFD,
    NoChildProcess,
    TryAgain,
    OutOfMemory,
    PermissionDenied,
    BadAddress,
    NotABlockDevice,
    DeviceBusy,
    FileExists,
    CrossDevLink,
    NoSuchDevice,
    NotADirectory,
    IsADirectory,
    InvalidArgument,
    FileTableOverflow,
    TooManyOpenFiles,
    NotATypeWriter,
    TextFileBusy,
    FileTooLarge,
    NoSpaceLeft,
    IllegalSeek,
    ReadOnlyFS,
    TooManyLinks,
    BrokenPipe,
    MathOutOfDomain,
    MathOutOfRange,
};

pub fn errorToErrno(err: SyscallError) isize {
    return switch (err) {
        SyscallError.NotPermitted => EPERM,
        SyscallError.NoSuchFile => ENOENT,
        SyscallError.NoSuchProcess => ESRCH,
        SyscallError.Interrupted => EINTR,
        SyscallError.IOError => EIO,
        SyscallError.NoSuchIO => ENXIO,
        SyscallError.ArgListTooLong => E2BIG,
        SyscallError.BadExecFormat => ENOEXEC,
        SyscallError.BadFD => EBADF,
        SyscallError.NoChildProcess => ECHILD,
        SyscallError.TryAgain => EAGAIN,
        SyscallError.OutOfMemory => ENOMEM,
        SyscallError.PermissionDenied => EACCES,
        SyscallError.BadAddress => EFAULT,
        SyscallError.NotABlockDevice => ENOTBLK,
        SyscallError.DeviceBusy => EBUSY,
        SyscallError.FileExists => EEXIST,
        SyscallError.CrossDevLink => EXDEV,
        SyscallError.NoSuchDevice => ENODEV,
        SyscallError.NotADirectory => ENOTDIR,
        SyscallError.IsADirectory => EISDIR,
        SyscallError.InvalidArgument => EINVAL,
        SyscallError.FileTableOverflow => ENFILE,
        SyscallError.TooManyOpenFiles => EMFILE,
        SyscallError.NotATypeWriter => ENOTTY,
        SyscallError.TextFileBusy => ETXTBSY,
        SyscallError.FileTooLarge => EFBIG,
        SyscallError.NoSpaceLeft => ENOSPC,
        SyscallError.IllegalSeek => ESPIPE,
        SyscallError.ReadOnlyFS => EROFS,
        SyscallError.TooManyLinks => EMLINK,
        SyscallError.BrokenPipe => EPIPE,
        SyscallError.MathOutOfDomain => EDOM,
        SyscallError.MathOutOfRange => ERANGE,
    };
}
