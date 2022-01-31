const std = @import("std");
const utils = @import("utils.zig");
pub const Signal = @import("scheduler.zig").Signal;
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const PAGE_SIZE = @import("memory/paging.zig").PAGE_SIZE;
const pageAllocator = Allocator{ .ptr = undefined, .vtable = &PageAllocator.vtable };
var generalPurposeAllocator = GeneralPurposeAllocator(.{}){ .backing_allocator = pageAllocator };
pub var userAllocator = generalPurposeAllocator.allocator();

pub fn read(fd: usize, buffer: []u8, count: usize) isize {
    return asm volatile (
        \\mov $0, %%eax
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
        \\mov $39, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> usize),
    );
}

pub fn fork() isize {
    return asm volatile (
        \\mov $57, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> isize),
    );
}

pub fn signal(sig: Signal, handler: fn () void) isize {
    return asm volatile (
        \\mov $57, %%eax
        : [ret] "=&{eax}" (-> isize),
        : [sig] "{ebx}" (@enumToInt(sig)),
          [hdl] "{ecx}" (@ptrToInt(handler)),
    );
}

pub fn exit() noreturn {
    asm volatile (
        \\mov $60, %%eax
        \\int $0x80
    );
    unreachable;
}

pub fn usage(ptr: *@import("memory/page_allocator.zig").PageAllocator.AllocatorUsage) isize {
    return asm volatile (
        \\mov $184, %%eax
        \\int $0x80
        : [ret] "=&{eax}" (-> isize),
        : [addr] "{ebx}" (ptr),
        : "memory"
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
