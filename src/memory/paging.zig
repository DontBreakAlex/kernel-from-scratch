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
    setupPaging() catch @panic("Failed to setup paging");
}

var kernelPageDirectory: *[1024]PageEntry = undefined;

pub fn setupPaging() !void {
    std.debug.assert(@sizeOf(PageEntry) * 1024 == 4096);

    const kPDAlloc = try pageAllocator.alloc();
    kernelPageDirectory = @intToPtr(*[1024]PageEntry, kPDAlloc);
    initEmpty(kernelPageDirectory);
    const first_dir_entry = &kernelPageDirectory[0];

    const page_table = try pageAllocator.alloc();

    first_dir_entry.flags = PRESENT | WRITE;
    first_dir_entry.phy_addr = @truncate(u20, page_table >> 12);

    const kernel_page_table = @intToPtr(*[1024]PageEntry, page_table);
    // Map first 1M of phy mem to first 1M of kernel virt mem
    for (kernel_page_table[0..256]) |*table_entry, i| {
        table_entry.flags = PRESENT | WRITE;
        table_entry.phy_addr = @truncate(u20, (0x1000 * i) >> 12);
    }
    var table: u32 = kernelPageDirectory[0].phy_addr;
    table <<= 12;
    initEmpty(kernel_page_table[256..1024]);
    try mapOneToOne(kPDAlloc);
    try mapOneToOne(page_table);
    var allocator_begin = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr), PAGE_SIZE);
    const allocator_end = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr) + pageAllocator.alloc_table.len, PAGE_SIZE);
    while (allocator_begin <= allocator_end) : (allocator_begin += PAGE_SIZE)
        try mapOneToOne(allocator_begin);

    asm volatile (
        \\mov %%eax, %%cr3
        \\mov %%cr0, %%eax
        \\or $0x80000001, %%eax
        \\mov %%eax, %%cr0
        :
        : [kernelPageDirectory] "{eax}" (kernelPageDirectory),
    );
}

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
        mapOneToOne(addr + i * 0x1000) catch |err| {
            if (err == MapError.AlreadyMapped)
                continue;
            return err;
        };
    }
}
pub fn allocAndMap() !usize {
    const allocated = try pageAllocator.alloc();
    try mapOneToOne(allocated);
    return allocated;
}

pub fn allocVirt(v_addr: usize, flags: u12) !void {
    const allocated = try pageAllocator.alloc();
    try mapVirtToPhy(v_addr, allocated, flags);
}

const MapError = error{
    AlreadyMapped,
    OutOfMemory,
};

pub fn mapOneToOne(addr: usize) MapError!void {
    return mapVirtToPhy(addr, addr, WRITE);
}

pub fn mapVirtToPhy(v_addr: usize, p_addr: usize, flags: u12) MapError!void {
    _ = flags;
    const dir_offset = @truncate(u10, (v_addr & 0b11111111110000000000000000000000) >> 22);
    const table_offset = @truncate(u10, (v_addr & 0b00000000000111111111100000000000) >> 12);
    const directory_entry = &kernelPageDirectory[dir_offset];
    if ((directory_entry.flags & PRESENT) == 0) {
        const allocated = try pageAllocator.alloc();
        directory_entry.flags = PRESENT | flags;
        directory_entry.phy_addr = @truncate(u20, allocated >> 12);
        try mapOneToOne(allocated);
        initEmpty(@intToPtr(*[1024]PageEntry, allocated));
    }
    const page_table_entry = &@intToPtr(*[1024]PageEntry, @intCast(usize, directory_entry.phy_addr) << 12)[table_offset];
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

pub fn unMap(v_addr: usize) void {
    const dir_offset = @truncate(u10, (v_addr & 0b11111111110000000000000000000000) >> 22);
    const table_offset = @truncate(u10, (v_addr & 0b00000000000111111111100000000000) >> 12);
    const directory_entry = &kernelPageDirectory[dir_offset];
    if ((directory_entry.flags & PRESENT) == 0)
        return;
    const page_table_entry = &@intToPtr(*[1024]PageEntry, @intCast(usize, directory_entry.phy_addr) << 12)[table_offset];
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
