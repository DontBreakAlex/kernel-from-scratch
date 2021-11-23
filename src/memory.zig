const PageEntry = packed struct {
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
    phy_addr: u20,
};

pub const PageAllocator = struct {
    base: usize,
    alloc_table: []bool,

    /// Base: where available memory starts
    /// Size: how mage pages (4Kib) are available
    pub fn init(base: usize, size: usize) PageAllocator {
        if (base % 0x1000 != 0)
            @panic("Unaligned memory in PageAllocator");
        const table_footprint = size % 0x1000;
        const alloc_table: []bool = @intToPtr([*]bool, base)[0..size - table_footprint];
        for (alloc_table) |*e| {
            e.* = false;
        }
        return PageAllocator{
            .base = base + 0x1000 * table_footprint,
            .alloc_table = alloc_table,
        };
    }

    /// Returns a single page of physical memory
    pub fn alloc(self: *PageAllocator) error.OutOfMemory!usize {
        for (self.alloc_table) |*e, i| {
            if (e.* == false) {
                e.* = true;
                return self.base + i * 0x1000;
            }
        }
        return error.OutOfMemory;
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
};

var ALLOCATOR: PageAllocator = undefined;

pub fn init(size: usize) void {
    ALLOCATOR = PageAllocator.init(0x100000, size / 4);
}
