const std = @import("std");
const utils = @import("utils.zig");
pub const Signal = @import("process.zig").Signal;
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const PAGE_SIZE = @import("memory/paging.zig").PAGE_SIZE;
const pageAllocator = Allocator{ .ptr = undefined, .vtable = &PageAllocator.vtable };
var generalPurposeAllocator = GeneralPurposeAllocator(.{ .safety = false, .stack_trace_frames = 0 }){ .backing_allocator = pageAllocator };
pub var userAllocator = generalPurposeAllocator.allocator();

pub fn read(fd: isize, buffer: []u8, count: usize) isize {
    return asm volatile (
        \\mov $3, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [fd] "{ebx}" (fd),
          [buf] "{ecx}" (buffer.ptr),
          [cnt] "{edx}" (count),
    );
}

pub fn write(fd: isize, buffer: []const u8, count: usize) isize {
    return asm volatile (
        \\mov $4, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [fd] "{ebx}" (fd),
          [buf] "{ecx}" (buffer.ptr),
          [cnt] "{edx}" (count),
    );
}

pub fn mmap(cnt: usize) ![]u8 {
    var buf = asm volatile (
        \\mov $9, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [cnt] "{ebx}" (cnt),
        : "eax", "memory"
    );
    if (buf == -1)
        return error.OutOfMemory;
    return @intToPtr([*]u8, @bitCast(usize, buf))[0 .. cnt * PAGE_SIZE];
}

pub fn munmap(buf: []u8) void {
    asm volatile (
        \\mov $11, %%eax
        \\int $0x80
        :
        : [addr] "{ebx}" (buf.ptr),
          [len] "{ecx}" (utils.divCeil(buf.len, PAGE_SIZE)),
        : "eax", "memory"
    );
}

pub fn getPid() usize {
    return asm volatile (
        \\mov $20, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> usize),
    );
}

pub fn getUid() usize {
    return asm volatile (
        \\mov $102, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> usize),
    );
}

pub fn fork() isize {
    return asm volatile (
        \\mov $2, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> isize),
    );
}

pub fn signal(sig: Signal, handler: fn () void) isize {
    return asm volatile (
        \\mov $48, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [sig] "{ebx}" (@enumToInt(sig)),
          [hdl] "{ecx}" (@ptrToInt(handler)),
    );
}

pub fn exit(code: usize) noreturn {
    asm volatile (
        \\mov $1, %%eax
        \\int $0x80
        :
        : [code] "{ebx}" (code),
    );
    unreachable;
}

pub fn wait() isize {
    return asm volatile (
        \\mov $7, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> isize),
    );
}

pub fn usage(ptr: *@import("memory/page_allocator.zig").PageAllocator.AllocatorUsage) isize {
    return asm volatile (
        \\mov $222, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [addr] "{ebx}" (ptr),
        : "memory"
    );
}

pub fn sleep() isize {
    return asm volatile (
        \\mov $162, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
    );
}

pub fn kill(pid: usize, sig: Signal) isize {
    return asm volatile (
        \\mov $37, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [pid] "{ebx}" (pid),
          [sig] "{ecx}" (@intCast(usize, @enumToInt(sig))),
    );
}

pub fn sigwait() isize {
    return asm volatile (
        \\mov $177, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
    );
}

pub fn pipe(fds: [2]isize) isize {
    return asm volatile (
        \\mov $42, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [fd] "{ebx}" (&fds),
    );
}

pub fn close(fd: isize) isize {
    return asm volatile (
        \\mov $6, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [fd] "{ebx}" (fd),
    );
}

pub fn command(cmd: usize) isize {
    return asm volatile (
        \\mov $223, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [cmd] "{ebx}" (cmd),
    );
}

pub fn getcwd(buf: []u8) isize {
    return asm volatile (
        \\mov $79, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [addr] "{ebx}" (buf.ptr),
          [len] "{ecx}" (buf.len),
        : "eax", "memory"
    );
}

pub fn chdir(buf: []const u8) isize {
    return asm volatile (
        \\mov $80, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [addr] "{ebx}" (buf.ptr),
          [len] "{ecx}" (buf.len),
        : "eax", "memory"
    );
}

const fs = @import("io/fs.zig");
pub const READ = fs.READ;
pub const WRITE = fs.WRITE;
pub const RW = fs.RW;
pub const DIRECTORY = fs.DIRECTORY;
pub fn open(path: []const u8, mode: u8) isize {
    return asm volatile (
        \\mov $5, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [addr] "{ebx}" (path.ptr),
          [len] "{ecx}" (path.len),
          [mode] "{edx}" (mode),
        : "eax", "memory"
    );
}

const dirent = @import("io/dirent.zig");
pub const Dentry = dirent.Dentry;
pub fn getdents(fd: isize, buffer: []Dentry) isize {
    return asm volatile (
        \\mov $78, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [fd] "{ebx}" (fd),
          [buf] "{ecx}" (buffer.ptr),
          [cnt] "{edx}" (buffer.len),
    );
}

pub fn sync() isize {
    return asm volatile (
        \\mov $36, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
    );
}

const PageAllocator = struct {
    const vtable = Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };

    fn alloc(_: *anyopaque, len: usize, alignment: u29, len_align: u29, ra: usize) ![]u8 {
        _ = ra;
        if (alignment > PAGE_SIZE)
            @panic("Unsuported aligned virtual alloc");
        const page_count = utils.divCeil(len, PAGE_SIZE);
        const buf = try mmap(page_count);
        return buf[0..std.mem.alignAllocLen(buf.len, len, len_align)];
    }

    fn resize(
        _: *anyopaque,
        _: []u8,
        _: u29,
        _: usize,
        _: u29,
        _: usize,
    ) ?usize {
        unreachable;
    }

    fn free(_: *anyopaque, buf: []u8, _: u29, _: usize) void {
        munmap(buf);
    }
};
