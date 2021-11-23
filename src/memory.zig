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
    size: usize,

    pub fn init(base: usize, size: usize) PageAllocator {
        if (base % 0x1000 != 0 or size % 0x1000 != 0)
            @panic("Unaligned memory in PageAllocator");
        if (size / 0x1000 >= 0x1000)
            @panic("Memory too big for PageAllocator");
        const alloc_table: []bool = @intToPtr([*]bool, base)[0..size];
        for (alloc_table) |*e| {
            e.* = false;
        }
        return PageAllocator{
            .base = base,
            .size = size,
        };
    }

    // Returns a single page of physical memory
    // fn alloc() !usize {

    // }
};

var ALLOCATOR: PageAllocator = undefined;

pub fn init(size: usize) void {
    ALLOCATOR = PageAllocator.init(0x100000, size - size % 0x1000);
}
