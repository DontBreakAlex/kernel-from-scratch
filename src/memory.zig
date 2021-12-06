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

const VMapNode = struct {
    addr: usize,
    size: usize,
    allocated: bool,
};

pub var pageAllocator: PageAllocator = undefined;

const phyBackAlloc: *Allocator = &pageAllocator.allocator;
var phyGpAlloc: GeneralPurposeAllocator(.{}) = GeneralPurposeAllocator(.{}){ .backing_allocator = phyBackAlloc };
pub const phyAllocator: *Allocator = &phyGpAlloc.allocator;
var virtBackAlloc: Allocator = Allocator{ .allocFn = allocFn, .resizeFn = resizeFn };
var virtGpAlloc: GeneralPurposeAllocator(.{}) = GeneralPurposeAllocator(.{}){ .backing_allocator = &virtBackAlloc };
pub const virtAllocator: *Allocator = &virtGpAlloc.allocator;

var kernelPageDirectory: *[1024]PageEntry = undefined;

pub fn init(size: usize) void {
    pageAllocator = PageAllocator.init(0x100000, size / 4);
}

const utils = @import("utils.zig");
const vga = @import("vga.zig");

pub fn setupPageging() !void {
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

pub fn allocAndMap() !usize {
    const allocated = try pageAllocator.alloc();
    try mapOneToOne(allocated);
    return allocated;
}

pub fn allocVirt(v_addr: usize, flags: u12) !void {
    const allocated = try pageAllocator.alloc();
    try mapVirtToPhy(v_addr, allocated, flags);
}

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
    vga.format("Reserved {x:0>8}-{x:0>8}\n", .{ std.mem.alignBackward(addr, PAGE_SIZE), std.mem.alignBackward(addr, PAGE_SIZE) + page_count * PAGE_SIZE });
}

pub fn sizeOf(buff: []u8) usize {
    return buff.len;
}

var vMemStackPointer: usize = 0x1000000;

/// Returns an adress in kernel vmem with `count` unmapped pages after it
pub fn findContinuousVirt(count: usize) usize {
    defer vMemStackPointer += count * 0x1000;
    return vMemStackPointer;
}

fn allocFn(self: *Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
    _ = self;
    _ = ret_addr;
    if (ptr_align > PAGE_SIZE)
        @panic("Unsuported aligned virtual alloc");
    const page_count = utils.divCeil(len, PAGE_SIZE);
    const v_addr = findContinuousVirt(page_count);
    var i: usize = 0;
    var addr = v_addr;
    while (i < page_count) {
        allocVirt(addr, WRITE) catch return Allocator.Error.OutOfMemory;
        i += 1;
        addr += PAGE_SIZE;
    }
    const requested_len = std.mem.alignAllocLen(page_count * PAGE_SIZE, len, len_align);
    // vga.format("Allocated: 0x{x:0>8}-0x{x:0>8}\n", .{ v_addr, v_addr + page_count * PAGE_SIZE });
    return @intToPtr([*]u8, v_addr)[0..requested_len];
}

fn resizeFn(self: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) !usize {
    _ = self;
    _ = buf;
    _ = buf_align;
    _ = new_len;
    _ = len_align;
    _ = ret_addr;
    if (new_len != 0)
        @panic("Attempt to resize virtual alloc");
    return 0;
}
