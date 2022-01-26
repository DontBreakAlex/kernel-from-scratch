const std = @import("std");
const Allocator = std.mem.Allocator;
const PAGE_SIZE = @import("paging.zig").PAGE_SIZE;
const utils = @import("../utils.zig");
const vga = @import("../vga.zig");

pub const PageAllocator = struct {
    base: usize,
    alloc_table: []bool,

    /// Base: where available memory starts
    /// Size: how mage pages (4Kib) are available
    pub fn init(base: usize, size: usize) PageAllocator {
        if (base % PAGE_SIZE != 0)
            @panic("Unaligned memory in PageAllocator");
        // Number of pages occupied by the allocation table
        const table_footprint = utils.divCeil(size, PAGE_SIZE);
        const alloc_table: []bool = @intToPtr([*]bool, base)[0 .. size - table_footprint];
        for (alloc_table) |*e| {
            e.* = false;
        }
        return PageAllocator{ .base = base + PAGE_SIZE * table_footprint, .alloc_table = alloc_table };
    }

    pub fn allocator(self: *PageAllocator) Allocator {
        return Allocator.init(self, allocFn, resizeFn, freeFn);
    }

    fn allocFn(self: *PageAllocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
        _ = ret_addr;
        const buf = if (ptr_align <= PAGE_SIZE)
            try self.allocPageAligned(len)
        else
            try self.allocAligned(len, ptr_align);
        if (len_align == 0) {
            return buf[0..len];
        } else if (len_align == 1) {
            return buf;
        } else {
            const requested_len = std.mem.alignAllocLen(buf.len, len, len_align);
            return buf[0..requested_len];
        }
    }

    fn freeFn(self: *PageAllocator, buf: []u8, buf_align: u29, ret_addr: usize) void {
        _ = ret_addr;
        const first_page = if (buf_align <= PAGE_SIZE) @ptrToInt(buf.ptr) else std.mem.alignBackward(@ptrToInt(buf.ptr), PAGE_SIZE);
        const last_page = std.mem.alignBackward(@ptrToInt(buf.ptr) + buf.len, PAGE_SIZE);
        const start = (first_page - self.base) / PAGE_SIZE;
        const end = (last_page - self.base) / PAGE_SIZE;

        self.multipleFree(start, end);
    }

    fn resizeFn(self: *PageAllocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = len_align;
        _ = ret_addr;
        unreachable;
    }

    /// Returns a single page of physical memory
    pub fn alloc(self: *PageAllocator) !usize {
        for (self.alloc_table) |*e, i| {
            if (e.* == false) {
                e.* = true;
                // vga.format("Allocated: 0x{x:0>8}\n", .{self.base + i * PAGE_SIZE});
                return self.base + i * PAGE_SIZE;
            }
        }
        return Allocator.Error.OutOfMemory;
    }

    pub fn allocPageAligned(self: *PageAllocator, size: usize) ![]u8 {
        const count = utils.divCeil(size, PAGE_SIZE);
        var continuous: usize = 0;
        for (self.alloc_table) |e, i| {
            if (e == false) {
                continuous += 1;
                if (continuous == count) {
                    const first_page = i + 1 - count;
                    const last_page = i + 1;
                    for (self.alloc_table[first_page..last_page]) |*p| {
                        p.* = true;
                    }
                    return @intToPtr([*]u8, self.base + first_page * PAGE_SIZE)[0..(count * PAGE_SIZE)];
                }
            } else {
                continuous = 0;
            }
        }
        return Allocator.Error.OutOfMemory;
    }

    pub fn allocAligned(self: *PageAllocator, size: usize, aligment: u29) ![]u8 {
        outer: for (self.alloc_table) |*e, i| {
            if (e.* == false) {
                const page_begin = self.base + i * PAGE_SIZE;
                const page_end = page_begin + PAGE_SIZE;
                const aligned = std.mem.alignForward(page_begin, aligment);

                // Check if pointer can be aligned inside the page
                if (aligned < page_end) {
                    const allocated = (page_end - aligned);
                    if (allocated >= size) {
                        e.* = true;
                        return @intToPtr([*]u8, aligned)[0..allocated];
                    }
                    const remaining = size - allocated;
                    const missing_pages = utils.divCeil(remaining, PAGE_SIZE);
                    // Check that next pages are free
                    for (self.alloc_table[i + 1 .. i + missing_pages + 1]) |f| {
                        if (f == true)
                            continue :outer;
                    }
                    for (self.alloc_table[i .. i + missing_pages + 1]) |*f| {
                        f.* = true;
                    }
                    const alloc_end = self.base + (i + missing_pages + 1) * PAGE_SIZE;
                    const alloc_size = alloc_end - aligned;
                    return @intToPtr([*]u8, aligned)[0..alloc_size];
                }
            }
        }
        return Allocator.Error.OutOfMemory;
    }

    /// Resizes a buffer (resizing to one will not free)
    pub fn resize(self: *PageAllocator, buf: []u8, new_len: usize) !usize {
        const last_allocated_page = (std.mem.alignBackward((@ptrToInt(buf.ptr) + buf.len), PAGE_SIZE) - self.base) / PAGE_SIZE;
        const new_last_page = (std.mem.alignBackward((@ptrToInt(buf.ptr) + new_len), PAGE_SIZE) - self.base) / PAGE_SIZE;
        for (self.alloc_table[last_allocated_page + 1 .. new_last_page + 1]) |e|
            if (e == true)
                return Allocator.Error.OutOfMemory;
        for (self.alloc_table[last_allocated_page + 1 .. new_last_page + 1]) |*e|
            e.* = true;
        return (new_last_page + 1) * PAGE_SIZE - @ptrToInt(buf.ptr);
    }

    /// Frees a single page
    pub fn free(self: *PageAllocator, addr: usize) void {
        if (addr % 0x1000 != 0)
            @panic("Attempt to free unaligned page");
        const index = (addr - self.base) / 0x1000;
        if (index >= self.alloc_table.len)
            @panic("Attempt to free non-existant page");
        if (self.alloc_table[index] == false)
            @panic("Page double free");
        self.alloc_table[index] = false;
    }

    /// Frees pages from start to end
    pub fn multipleFree(self: *PageAllocator, start: usize, end: usize) void {
        for (self.alloc_table[start .. end + 1]) |*e| {
            e.* = false;
        }
    }

    const ReserveError = error{
        OutOfMemory,
        AllreadyAllocated,
    };

    /// Attemps to mark a page allocated
    pub fn reserve(self: *PageAllocator, addr: usize, count: usize) !void {
        if (addr < self.base)
            return ReserveError.OutOfMemory;
        const index = (addr - self.base) / 0x1000;
        const pages = self.alloc_table[index .. index + count];
        if (index >= self.alloc_table.len or index + count > self.alloc_table.len)
            return ReserveError.OutOfMemory;
        // This is disabled because it causes issues when trying to reserve structures that share pages
        // for (pages) |p| if (p == true)
        //     return ReserveError.AllreadyAllocated;
        for (pages) |*p| p.* = true;
    }
};
