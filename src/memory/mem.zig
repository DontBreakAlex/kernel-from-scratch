const std = @import("std");
const paging = @import("paging.zig");
const vmem = @import("vmem.zig");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const PageAllocator = @import("page_allocator.zig").PageAllocator;
const VMemManager = vmem.VMemManager;
const VirtualAllocator = vmem.VirtualAllocator;
const PageDirectory = paging.PageDirectory;

var vmemManager = VMemManager{};
var virtualAllocator = VirtualAllocator{ .vmem = &vmemManager, .paging = &paging.kernelPageDirectory };
var generalPurposeAllocator: GeneralPurposeAllocator(.{}) = GeneralPurposeAllocator(.{}){ .backing_allocator = &virtualAllocator.allocator };
pub const allocator: *Allocator = &generalPurposeAllocator.allocator;

pub fn init(size: usize) void {
    paging.init(size / 4);
    vmemManager.init();
}

const PAGE_SIZE = paging.PAGE_SIZE;

pub fn mapStructure(comptime T: type, ptr: *T, cr3: *const PageDirectory) *T {
    const first_page = std.mem.alignBackward(ptr, PAGE_SIZE);
    const last_page = std.mem.alignBackward(ptr + @sizeOf(T), PAGE_SIZE);
    if (first_page == last_page) {
        // Whole structure is one page;
        const p_addr = if (cr3.virtToPhy(@ptrToInt(ptr))) |a| a else @panic("Attempt to map invalid phy_addr");
        const v_addr = vmemManager.alloc(1);
        paging.kernelPageDirectory.mapVirtToPhy(v_addr, p_addr, paging.WRITE);
        return @intToPtr(*T, v_addr);
    } else {
        // Structure spans around multiple pages
        const page_count = (last_page - first_page) / PAGE_SIZE;
        var p_addr = if (cr3.virtToPhy(@ptrToInt(ptr))) |a| a else @panic("Attempt to map invalid phy_addr");
        var v_addr = vmemManager.alloc(page_count);
    }
}
