const std = @import("std");
const Allocator = std.mem.Allocator;
const PAGE_SIZE = @import("paging.zig").PAGE_SIZE;
const utils = @import("../utils.zig");
const vga = @import("../vga.zig");
const serial = @import("../serial.zig");

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
        if (ptr_align > PAGE_SIZE)
            @panic("Unsuported page align");
        const page_count = utils.divCeil(len, PAGE_SIZE);
        const buf = try self.allocMultiple(page_count);
        return buf[0..std.mem.alignAllocLen(buf.len, len, len_align)];
    }

    fn freeFn(self: *PageAllocator, buf: []u8, _: u29, _: usize) void {
        const page_count = utils.divCeil(buf.len, PAGE_SIZE);
        var i: usize = 0;
        while (i < page_count) : (i += 1) {
            _ = self.free(buf.ptr + PAGE_SIZE * i) catch unreachable;
        }
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
        for (self.alloc_table) |e, i| {
            if (e == false) {
                self.markAllocated(i);
                return self.base + i * PAGE_SIZE;
            }
        }
        return Allocator.Error.OutOfMemory;
    }

    pub fn allocMultiple(self: *PageAllocator, count: usize) ![]u8 {
        var continuous: usize = 0;
        for (self.alloc_table) |e, i| {
            if (e == false) {
                continuous += 1;
                if (continuous == count) {
                    const first_page = i + 1 - count;
                    const last_page = i + 1;
                    var o = first_page;
                    while (o <= last_page) : (o += 1)
                        self.markAllocated(o);
                    return @intToPtr([*]u8, self.base + first_page * PAGE_SIZE)[0..(count * PAGE_SIZE)];
                }
            } else {
                continuous = 0;
            }
        }
        return Allocator.Error.OutOfMemory;
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
        self.markFree(index);
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

    fn markAllocated(self: *PageAllocator, index: usize) void {
        self.alloc_table[index] = true;
        serial.format("Allocated 0x{x:0>8}\n", .{ self.base + index * PAGE_SIZE });
    }

    fn markFree(self: *PageAllocator, index: usize) void {
        self.alloc_table[index] = false;
        serial.format("Freed 0x{x:0>8}\n", .{ self.base + index * PAGE_SIZE });
    }

    /// Holds memory usage
    pub const AllocatorUsage = struct {
        /// Pages managed by this allocator
        capacity: usize,
        /// Allocated pages
        allocated: usize,
    };

    pub fn usage(self: *PageAllocator) AllocatorUsage {
        var i: usize = 0;
        for (self.alloc_table) |e| {
            if (e) i += 1;
        }
        return AllocatorUsage {
            .capacity = self.alloc_table.len,
            .allocated = i,
        };
    }
};
