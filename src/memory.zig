pub const PAGE_SIZE = 0x1000;
const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const PageAllocator = @import("memory/page_allocator.zig").PageAllocator;
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

const PRESENT: u12 = 0b1;
const WRITE: u12 = 0b10;
const USER: u12 = 0b100;

const PageEntry = packed struct {
    flags: u12,
    phy_addr: u20,
};

const MapError = error{
    AlreadyMapped,
    OutOfMemory,
};

pub var pageAllocator: PageAllocator = undefined;

const phyBackAlloc: *Allocator = &pageAllocator.allocator;
var phyGpAlloc: GeneralPurposeAllocator(.{}) = undefined;
pub const phyAllocator: *Allocator = &phyGpAlloc.allocator;

var kernelPageDirectories: *[1024]PageEntry = undefined;

pub fn init(size: usize) void {
    pageAllocator = PageAllocator.init(0x100000, size / 4);
    phyGpAlloc = GeneralPurposeAllocator(.{}){ .backing_allocator = phyBackAlloc };
}

const utils = @import("utils.zig");
const vga = @import("vga.zig");

pub fn setupPageging() !void {
    std.debug.assert(@sizeOf(PageEntry) * 1024 == 4096);

    const kPDAlloc = try pageAllocator.alloc();
    kernelPageDirectories = @intToPtr(*[1024]PageEntry, kPDAlloc);
    initEmpty(kernelPageDirectories);
    const first_dir = &kernelPageDirectories[0];

    const pageTables = try pageAllocator.alloc();

    first_dir.flags = PRESENT | WRITE;
    first_dir.phy_addr = @truncate(u20, pageTables >> 12);

    const kernel_page_tables = @intToPtr(*[1024]PageEntry, pageTables);
    // Map first 1M of phy mem to first 1M of kernel virt mem
    for (kernel_page_tables[0..256]) |*table, i| {
        table.flags = PRESENT | WRITE;
        table.phy_addr = @truncate(u20, (0x1000 * i) >> 12);
    }
    var tab: u32 = kernelPageDirectories[0].phy_addr;
    tab <<= 12;
    vga.format("{b:0>32}\n", .{@intToPtr(*u32, tab).*});
    initEmpty(kernel_page_tables[256..1024]);
    try mapOneToOne(kPDAlloc);
    try mapOneToOne(pageTables);
    var allocator_begin = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr), PAGE_SIZE);
    const allocator_end = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr) + pageAllocator.alloc_table.len, PAGE_SIZE);
    while (allocator_begin <= allocator_end) : (allocator_begin += PAGE_SIZE)
        try mapOneToOne(allocator_begin);

    vga.format("{b:0>32}\n", .{@intToPtr(*u32, tab).*});
    // vga.format("0x{x:0>8}\n", .{ talbe });
    asm volatile (
        \\mov %%eax, %%cr3
        \\mov %%cr0, %%eax
        \\or $0x80000001, %%eax
        \\mov %%eax, %%cr0
        :
        : [kernelPageDirectories] "{eax}" (kernelPageDirectories),
    );
}

fn initEmpty(entries: []PageEntry) void {
    for (entries) |*e| {
        e.flags = 0;
        e.phy_addr = 0;
    }
}

pub fn allocAndMap() !usize {
    const allocated = try pageAllocator.alloc();
    try mapOneToOne(allocated);
    return allocated;
}

pub fn allocVirt(vaddr: usize, user: u1, write: u1) !void {
    const allocated = try pageAllocator.alloc();
    try mapVirtToPhy(vaddr, allocated, user, write);
}

pub fn mapOneToOne(addr: usize) MapError!void {
    return mapVirtToPhy(addr, addr, WRITE);
}

pub fn mapVirtToPhy(v_addr: usize, p_addr: usize, flags: u12) MapError!void {
    _ = flags;
    const dir_offset = @truncate(u10, (v_addr & 0b11111111110000000000000000000000) >> 22);
    const table_offset = @truncate(u10, (v_addr & 0b00000000000111111111100000000000) >> 12);
    const page_dir = &kernelPageDirectories[dir_offset];
    if ((page_dir.flags & PRESENT) == 0) {
        const allocated = try pageAllocator.alloc();
        page_dir.flags = PRESENT | flags;
        page_dir.phy_addr = @truncate(u20, allocated >> 12);
        try mapOneToOne(allocated);
        initEmpty(@intToPtr(*[1024]PageEntry, allocated));
    }
    const page_table = &@intToPtr(*[1024]PageEntry, page_dir.phy_addr)[table_offset];
    if ((page_table.flags & PRESENT) == 1) {
        return MapError.AlreadyMapped;
    }
    page_dir.flags = PRESENT | flags;
    page_table.phy_addr = @truncate(u20, p_addr >> 12);
}

pub fn sizeOf(buff: []u8) usize {
    return buff.len;
}

// fn allocFn(self: *Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) ![]u8 {

// }

// fn resizeFn(self: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) !usize {

// }
