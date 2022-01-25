const std = @import("std");
const Allocator = std.mem.Allocator;
const PAGE_SIZE = @import("memory/paging.zig").PAGE_SIZE;

pub fn read(fd: usize, buffer: []u8, count: usize) isize {
    return asm volatile (
        \\mov $0, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> isize),
        : [fd] "{ebx}" (fd),
          [buf] "{ecx}" (buffer.ptr),
          [cnt] "{edx}" (count),
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
        if (alignment> PAGE_SIZE)
            @panic("Unsuported aligned virtual alloc");
        const page_count = utils.divCeil(len, PAGE_SIZE);
    }

    fn resize(
        _: *anyopaque,
        buf_unaligned: []u8,
        buf_align: u29,
        new_size: usize,
        len_align: u29,
        return_address: usize,
    ) ?usize {
        _ = buf_align;
        _ = return_address;
        
        unreachable;
    }

    fn free(_: *anyopaque, buf_unaligned: []u8, buf_align: u29, return_address: usize) void {
        _ = buf_align;
        _ = return_address;
    }
};