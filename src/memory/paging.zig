const std = @import("std");
const utils = @import("../utils.zig");
const PageAllocator = @import("page_allocator.zig").PageAllocator;

pub const PRESENT: u12 = 0b1;
pub const WRITE: u12 = 0b10;
pub const USER: u12 = 0b100;

const PageEntry = packed struct {
    flags: u12,
    phy_addr: u20,
};

pub const PAGE_SIZE = 0x1000;
pub var pageAllocator: PageAllocator = undefined;

pub fn init(size: usize) void {
    pageAllocator = PageAllocator.init(0x100000, size);
    setup() catch @panic("Failed to setup paging");
}

fn setup() !void {
    kernelPageDirectory = PageDirectory{ .cr3 = @intToPtr(*[1024]PageEntry, try pageAllocator.alloc()) };
    try kernelPageDirectory.mapOneToOne(@ptrToInt(kernelPageDirectory.cr3));

    // Map first 1M of memory (where the kernel is)
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try kernelPageDirectory.mapOneToOne(0x1000 * i);
    }

    var allocator_begin = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr), PAGE_SIZE);
    const allocator_end = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr) + pageAllocator.alloc_table.len, PAGE_SIZE);
    while (allocator_begin <= allocator_end) : (allocator_begin += PAGE_SIZE)
        try kernelPageDirectory.mapOneToOne(allocator_begin);
    kernelPageDirectory.load();
    asm volatile(
        \\mov %%cr0, %%eax
        \\or $0x80000001, %%eax
        \\mov %%eax, %%cr0
        : : : "eax"
    );
}

pub var kernelPageDirectory: PageDirectory = undefined;

/// Manages a page directory
/// The kernel page directory must loaded for these function to work
pub const PageDirectory = struct {
    cr3: *[1024]PageEntry,

    pub fn init() PageDirectory!void {
        const allocated = try pageAllocator.alloc();
        try kernelPageDirectory.mapOneToOne(allocated);
        const cr3 = @intToPtr(*[1024]PageEntry, allocated);
        initEmpty(cr3);

        return PageDirectory{ .cr3 = cr3 };
    }

    pub fn mapOneToOne(self: *PageDirectory, addr: usize) MapError!void {
        return self.mapVirtToPhy(addr, addr, WRITE);
    }

    pub fn mapVirtToPhy(self: *PageDirectory, v_addr: usize, p_addr: usize, flags: u12) MapError!void {
        const dir_offset = @truncate(u10, (v_addr & 0b11111111110000000000000000000000) >> 22);
        const table_offset = @truncate(u10, (v_addr & 0b00000000000111111111100000000000) >> 12);
        const page_table = &self.cr3[dir_offset];
        if ((page_table.flags & PRESENT) == 0) {
            const allocated = try pageAllocator.alloc();
            page_table.flags = PRESENT | flags;
            page_table.phy_addr = @truncate(u20, allocated >> 12);
            try kernelPageDirectory.mapOneToOne(allocated);
            initEmpty(@intToPtr(*[1024]PageEntry, allocated));
        }
        const page_table_entry = &@intToPtr(*[1024]PageEntry, @intCast(usize, page_table.phy_addr) << 12)[table_offset];
        if ((page_table_entry.flags & PRESENT) == 1) {
            return MapError.AlreadyMapped;
        }
        page_table_entry.flags = PRESENT | flags;
        page_table_entry.phy_addr = @truncate(u20, p_addr >> 12);
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (v_addr),
            : "memory"
        );
    }

    pub fn unMap(self: *PageDirectory, v_addr: usize) void {
        const dir_offset = @truncate(u10, (v_addr & 0b11111111110000000000000000000000) >> 22);
        const table_offset = @truncate(u10, (v_addr & 0b00000000000111111111100000000000) >> 12);
        const page_table = &self.cr3[dir_offset];
        if ((page_table.flags & PRESENT) == 0)
            return;
        const page_table_entry = &@intToPtr(*[1024]PageEntry, @intCast(usize, page_table.phy_addr) << 12)[table_offset];
        if ((page_table_entry.flags & PRESENT) == 0)
            return;
        page_table_entry.flags = 0;
        page_table_entry.phy_addr = 0;
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (v_addr),
            : "memory"
        );
    }

    pub fn allocVirt(self: *PageDirectory, v_addr: usize, flags: u12) !void {
        const allocated = try pageAllocator.alloc();
        try self.mapVirtToPhy(v_addr, allocated, flags);
    }

    pub fn allocPhy(self: *PageDirectory) !usize {
        const allocated = try pageAllocator.alloc();
        try self.mapOneToOne(allocated);
        return allocated;
    }

    pub fn load(self: PageDirectory) void {
        // TODO: Enable paging outside
        asm volatile (
            \\mov %[pd], %%cr3
            :
            : [pd] "r" (self.cr3),
        );
    }
};

fn initEmpty(entries: []PageEntry) void {
    for (entries) |*e| {
        e.flags = 0;
        e.phy_addr = 0;
    }
}

/// Reserves and map a physical structure
pub fn reserveAndMap(addr: usize, size: usize) !void {
    const page_count = utils.divCeil((addr % PAGE_SIZE) + size, PAGE_SIZE);
    try pageAllocator.reserve(addr, page_count);
    var i: usize = 0;
    while (i < page_count) : (i += 1) {
        kernelPageDirectory.mapOneToOne(addr + i * 0x1000) catch |err| {
            if (err == MapError.AlreadyMapped)
                continue;
            return err;
        };
    }
}

const MapError = error{
    AlreadyMapped,
    OutOfMemory,
};
