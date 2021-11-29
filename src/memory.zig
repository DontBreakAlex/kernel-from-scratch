const Flags = packed struct {
    present: u1,
    /// 0 = ro, 1 = rw
    write: u1,
    /// 0 = supervisor only, 1 = public
    user: u1,
    /// 1 = disable write cache
    pwt: u1,
    /// 1 = disable cache
    pcd: u1,
    accessed: u1,
    dirty: u1,
    /// 0 = 4Kib, 1 = 4Mib. Set to 0
    size: u1,
    available: u4,
};

const PageEntry = packed struct {
    flags: Flags,
    phy_addr: u20,
};

const PAGE_SIZE = 0x1000;
const std = @import("std");
const utils = @import("utils.zig");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;


// TODO: Make sure we don't overwrite multiboot structures

pub const PageAllocator = struct {
    base: usize,
    alloc_table: []bool,
    allocator: Allocator,

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
        return PageAllocator{ .base = base + PAGE_SIZE * table_footprint, .alloc_table = alloc_table, .allocator = Allocator{
            .allocFn = allocFn,
            .resizeFn = resizeFn,
        } };
    }

    fn allocFn(parent: *Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {
        _ = ret_addr;
        const self: *PageAllocator = @fieldParentPtr(PageAllocator, "allocator", parent);
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

    fn resizeFn(parent: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) !usize {
        _ = ret_addr;
        const self: *PageAllocator = @fieldParentPtr(PageAllocator, "allocator", parent);
        if (new_len == 0) {
            const first_page = if (buf_align <= PAGE_SIZE) @ptrToInt(buf.ptr) else std.mem.alignBackward(@ptrToInt(buf.ptr), PAGE_SIZE);
            const last_page = std.mem.alignBackward(@ptrToInt(buf.ptr) + buf.len, PAGE_SIZE);
            const start = (first_page - self.base) / PAGE_SIZE;
            const end = (last_page - self.base) / PAGE_SIZE;

            self.multipleFree(start, end);
            return 0;
        } else if (new_len <= buf.len) {
            return new_len;
        } else {
            const size = try self.resize(buf, new_len);
            return if (len_align == 0) new_len else if (len_align == 1) size else std.mem.alignAllocLen(size, new_len, len_align);
        }
    }

    /// Returns a single page of physical memory
    pub fn alloc(self: *PageAllocator) !usize {
        for (self.alloc_table) |*e, i| {
            if (e.* == false) {
                e.* = true;
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
};

pub var pageAllocator: PageAllocator = undefined;
const backingAllocator: *Allocator = &pageAllocator.allocator;
var generalPurposeAllocator: GeneralPurposeAllocator(.{}) = undefined;
pub const allocator: *Allocator = &generalPurposeAllocator.allocator;

pub fn init(size: usize) void {
    pageAllocator = PageAllocator.init(0x100000, size / 4);
    generalPurposeAllocator = GeneralPurposeAllocator(.{}){ .backing_allocator = backingAllocator };
}

var kernelPageDirectories: *[1024]PageEntry = undefined;

fn initEmpty(entries: []PageEntry) void {
	for (entries) |*e| {
        e.* = PageEntry{
            .flags = Flags{
                .present = 0,
                .write = 0,
                .user = 0,
                .pwt = 0,
                .pcd = 0,
                .accessed = 0,
                .dirty = 0,
                .size = 0,
                .available = 0,
            },
            .phy_addr = 0,
        };
    }
}

const vga = @import("vga.zig");

pub fn setupPageging() !void {
    std.debug.assert(@sizeOf(PageEntry) * 1024 == 4096);

	const kPDAlloc = try pageAllocator.alloc();
	defer mapOneToOne(kPDAlloc);
    kernelPageDirectories = @intToPtr(*[1024]PageEntry, kPDAlloc);
    initEmpty(kernel_page_tables);
    const first_dir = &kernelPageDirectories[0];

    const pageTables = try pageAllocator.alloc();
	defer mapOneToOne(pageTables);

    first_dir.flags.present = 1;
    first_dir.flags.write = 1;
    first_dir.phy_addr = @truncate(u20, pageTables >> 12);

    const kernel_page_tables = @intToPtr(*[1024]PageEntry, pageTables);
    // Map first 1M of phy mem to first 1M of kernel virt mem
    for (kernel_page_tables[0..256]) |*table, i| {
        table.* = PageEntry{
            .flags = Flags{
                .present = 1,
                .write = 1,
                .user = 0,
                .pwt = 0,
                .pcd = 0,
                .accessed = 0,
                .dirty = 0,
                .size = 0,
                .available = 0,
            },
            .phy_addr = @truncate(u20, (0x1000 * i) >> 12),
        };
    }
    initEmpty(kernel_page_tables[256..1024]);
    mapOneToOne(0x100001) catch @panic("Not enough memory for page mapping\n");
}

pub fn mapOneToOne(addr: usize) !void {
    const dir_offset = @truncate(u10, (addr & 0b11111111110000000000000000000000) >> 22);
    const table_offset = @truncate(u10, (addr & 0b00000000000111111111100000000000) >> 12);
	const page_dir = &kernelPageDirectories[dir_offset];
	if (!page_dir.flags.present) {
		const allocated = try pageAllocator.alloc();
		page_dir.flags.present = 1;
		page_dir.flags.write = 1;
		page_dir.phy_addr = @truncate(u20, allocated >> 12);
		mapOneToOne(allocated);
		initEmpty(@intToPtr(*[1024]PageEntry, allocated));
	}
	const page_table = &@intToPtr(*[1024]PageEntry, page_dir.phy_addr)[table_offset];
	if (page_table.flags.present) {
		return error.AlreadyMapped;
	}
	page_table.flags.present = 1;
	page_table.flags.write = 1;
	page_table.phy_addr = @truncate(u20, addr >> 12);
}

pub fn allocAndMap() usize !void {
	const allocated = try pageAllocator.alloc();
	try mapOneToOne(allocated);
	return allocated;
}