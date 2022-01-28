const std = @import("std");
const utils = @import("../utils.zig");
const PageAllocator = @import("page_allocator.zig").PageAllocator;
const vga = @import("../vga.zig");
const serial = @import("../serial.zig");

pub const PRESENT: u12 = 0b1;
pub const WRITE: u12 = 0b10;
pub const USER: u12 = 0b100;
pub const ALLOCATING: u12 = 0b100000000000;

pub const PageEntry = packed struct {
    flags: u12,
    phy_addr: u20,
};

pub const PAGE_SIZE = 0x1000;
pub var pageAllocator: PageAllocator = undefined;

pub fn init(size: usize) void {
    pageAllocator = PageAllocator.init(0x100000, size);
    setup() catch |err| {
        vga.format("Paging error: {s}\n", .{err});
        @panic("Failed to setup paging");
    };
}

fn setup() !void {
    const dir_alloc = try pageAllocator.alloc();
    const tab_alloc = try pageAllocator.alloc();
    const dir = @intToPtr(*[1024]PageEntry, dir_alloc);
    const tab = @intToPtr(*[1024]PageEntry, tab_alloc);
    initEmpty(dir);
    initEmpty(tab);
    dir[0].flags = PRESENT | WRITE;
    dir[0].phy_addr = @truncate(u20, tab_alloc >> 12);
    kernelPageDirectory = PageDirectory{ .cr3 = dir };
    vga.format("Kernel cr3: 0x{x:0>8}\n", .{dir_alloc});

    try kernelPageDirectory.mapOneToOne(dir_alloc);
    try kernelPageDirectory.mapOneToOne(tab_alloc);
    printDirectory(kernelPageDirectory.cr3);

    // Map first 1M of memory (where the kernel is)
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try kernelPageDirectory.mapOneToOne(0x1000 * i);
    }

    var allocator_begin = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr), PAGE_SIZE);
    const allocator_end = std.mem.alignBackward(@ptrToInt(pageAllocator.alloc_table.ptr) + pageAllocator.alloc_table.len, PAGE_SIZE);
    while (allocator_begin <= allocator_end) : (allocator_begin += PAGE_SIZE)
        try kernelPageDirectory.mapOneToOne(allocator_begin);
    // try kernelPageDirectory.allocVirt(0x1000000 - 0x1000, WRITE);
    kernelPageDirectory.load();
    asm volatile (
        \\mov %%cr0, %%eax
        \\or $0x80000001, %%eax
        \\mov %%eax, %%cr0
        ::: "eax");
}

pub var kernelPageDirectory: PageDirectory = undefined;

/// Manages a page directory
/// The kernel page directory must loaded for these function to work
pub const PageDirectory = struct {
    cr3: *[1024]PageEntry,

    pub fn init() !PageDirectory {
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
        const table_offset = @truncate(u10, (v_addr & 0b00000000001111111111100000000000) >> 12);
        const page_table = &self.cr3[dir_offset];
        if ((page_table.flags & PRESENT) == 0) {
            const allocated = try pageAllocator.alloc();
            page_table.flags = PRESENT | WRITE;
            page_table.phy_addr = @truncate(u20, allocated >> 12);
            try kernelPageDirectory.mapOneToOne(allocated);
            initEmpty(@intToPtr(*[1024]PageEntry, allocated));
        }
        const page_table_entry = &@intToPtr(*[1024]PageEntry, @intCast(usize, page_table.phy_addr) << 12)[table_offset];
        if ((page_table_entry.flags & PRESENT) == 1) {
            const phy_addr = @intCast(usize, page_table_entry.phy_addr) << 12;
            if (p_addr == phy_addr)
                return;
            vga.format("AlreadyMapped: {*}, {x}\n0x{x:0>8} 0x{x:0>8}\n", .{ page_table_entry, page_table_entry, phy_addr, p_addr });
            return MapError.AlreadyMapped;
        }
        page_table_entry.flags = PRESENT | flags;
        page_table_entry.phy_addr = @truncate(u20, p_addr >> 12);
        // vga.format("Mapped: 0x{x:0>8}\n", .{v_addr});
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (v_addr),
            : "memory"
        );
    }

    pub fn unMap(self: *PageDirectory, v_addr: usize) MapError!usize {
        const dir_offset = @truncate(u10, (v_addr & 0b11111111110000000000000000000000) >> 22);
        const table_offset = @truncate(u10, (v_addr & 0b00000000001111111111000000000000) >> 12);
        const page_table = &self.cr3[dir_offset];
        if ((page_table.flags & PRESENT) == 0)
            return MapError.NotMapped;
        const page_table_entry = &@intToPtr(*[1024]PageEntry, @intCast(usize, page_table.phy_addr) << 12)[table_offset];
        if ((page_table_entry.flags & PRESENT) == 0)
            return MapError.NotMapped;
        const ret = @intCast(usize, page_table_entry.phy_addr) << 12 | (v_addr & 0b111111111111);
        page_table_entry.flags = 0;
        page_table_entry.phy_addr = 0;
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (v_addr),
            : "memory"
        );
        return ret;
    }

    pub fn allocVirt(self: *PageDirectory, v_addr: usize, flags: u12) !void {
        const allocated = try pageAllocator.alloc();
        try self.mapVirtToPhy(v_addr, allocated, flags);
    }

    pub fn freeVirt(self: *PageDirectory, v_addr: usize) !void {
        const phy = try self.unMap(v_addr);
        pageAllocator.free(phy);
    }

    pub fn allocPhy(self: *PageDirectory) !usize {
        const allocated = try pageAllocator.alloc();
        try self.mapOneToOne(allocated);
        return allocated;
    }

    pub fn load(self: *const PageDirectory) void {
        asm volatile (
            \\mov %[pd], %%cr3
            :
            : [pd] "r" (self.cr3),
        );
    }

    pub fn virtToPhy(self: *const PageDirectory, v_addr: usize) ?usize {
        const dir_offset = @truncate(u10, (v_addr & 0b11111111110000000000000000000000) >> 22);
        const table_offset = @truncate(u10, (v_addr & 0b00000000001111111111000000000000) >> 12);
        const page_table = &self.cr3[dir_offset];
        if ((page_table.flags & PRESENT) == 0)
            return null;
        const page_table_entry = &@intToPtr(*[1024]PageEntry, @intCast(usize, page_table.phy_addr) << 12)[table_offset];
        if ((page_table_entry.flags & PRESENT) == 0)
            return null;
        return @intCast(usize, page_table_entry.phy_addr) << 12 | (v_addr & 0b111111111111);
    }

    pub fn dup(self: *PageDirectory) !PageDirectory {
        var new: PageDirectory = try PageDirectory.init();
        vga.format("Duped cr3: {x}\n", .{new});
        for (self.cr3) |*page_table, dir_offset| {
            if (page_table.flags & PRESENT == 1) {
                for (@intToPtr(*[1024]PageEntry, @intCast(usize, page_table.phy_addr) << 12)) |*entry, table_offset| {
                    if (entry.flags & PRESENT == 1) {
                        const v_addr: usize = dir_offset << 22 | table_offset << 12;
                        const p_addr = @intCast(usize, entry.phy_addr) << 12;
                        if (v_addr != p_addr) {
                            const phy_mem = @intToPtr(*[PAGE_SIZE]u8, p_addr);
                            const new_mem = @intToPtr(*[PAGE_SIZE]u8, try pageAllocator.alloc());
                            kernelPageDirectory.mapOneToOne(@ptrToInt(phy_mem)) catch |err| if (err != MapError.AlreadyMapped) return err;
                            kernelPageDirectory.mapOneToOne(@ptrToInt(new_mem)) catch |err| if (err != MapError.AlreadyMapped) return err;
                            std.mem.copy(u8, new_mem, phy_mem);
                            try new.mapVirtToPhy(v_addr, @ptrToInt(new_mem), WRITE | PRESENT);
                            _ = try kernelPageDirectory.unMap(@ptrToInt(phy_mem));
                            _ = try kernelPageDirectory.unMap(@ptrToInt(new_mem));
                        } else {
                            try new.mapOneToOne(v_addr);
                        }
                    }
                }
            }
        }
        return new;
    }

    pub fn deinit(self: *PageDirectory) void {
        _ = self;
        // Iter over all pages
        // If present
        //  If phy_addr > 0x100000
        //   Dealloc phy_addr
        //  Unmap One-To-One
        //  Dealloc page
        for (self.cr3) |*tables| {
            for (tables) |table_entry| {
                unreachable;
            }
        }
    }
};

fn initEmpty(entries: []PageEntry) void {
    // vga.format("Zeroed: 0x{x:0>8}-0x{x:0>8}\n", .{ @ptrToInt(entries.ptr), @ptrToInt(entries.ptr) + entries.len * @sizeOf(PageEntry) });
    for (entries) |*e| {
        e.flags = 0;
        e.phy_addr = 0;
    }
}

fn printDirectory(entries: []PageEntry) void {
    vga.format("Page Directory: 0x{x:0>8}-0x{x:0>8}\n", .{ @ptrToInt(entries.ptr), @ptrToInt(entries.ptr) + entries.len * @sizeOf(PageEntry) });
    for (entries) |*e| {
        if (e.flags & PRESENT == 1) {
            const addr = @intCast(usize, e.phy_addr) << 12;
            vga.format("  Page Table: 0x{x:0>8}-0x{x:0>8}\n", .{ addr, addr + @sizeOf(PageEntry) * 1024 });
            printTable(@intToPtr(*[1024]PageEntry, addr));
        }
    }
}

fn printTable(entries: []PageEntry) void {
    for (entries) |*e| {
        if (e.flags & PRESENT == 1) {
            const addr = @intCast(usize, e.phy_addr) << 12;
            vga.format("    0x{x:0>8}\n", .{addr});
        }
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

pub fn printKernelPD() void {
    printDirectory(kernelPageDirectory.cr3);
}

const MapError = error{
    AlreadyMapped,
    OutOfMemory,
    NotMapped,
};
