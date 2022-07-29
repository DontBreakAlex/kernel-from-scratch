const std = @import("std");
const paging = @import("paging.zig");
const vmem = @import("vmem.zig");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const VMemManager = vmem.VMemManager;
const VirtualAllocator = vmem.VirtualAllocator;
const PageDirectory = paging.PageDirectory;

var vmemManager = VMemManager{};
var virtualAllocator = VirtualAllocator{ .vmem = &vmemManager, .paging = &paging.kernelPageDirectory };
var generalPurposeAllocator = GeneralPurposeAllocator(.{ .safety = false, .stack_trace_frames = 0 }){ .backing_allocator = virtualAllocator.allocator() };
pub const allocator: Allocator = generalPurposeAllocator.allocator();

pub fn init(size: usize) void {
    paging.init(size / 4);
    vmemManager.init();
}

const PAGE_SIZE = paging.PAGE_SIZE;

pub fn allocKstack(page_count: usize, user_pd: PageDirectory) !usize {
    // Alloc one more page that will not be mapped to trigger a page fault when the stack overflows
    const first_page = try vmemManager.alloc(page_count + 1);
    const last_page = first_page + PAGE_SIZE * page_count;
    var i: usize = 0;
    while (i < page_count) : (i += 1) {
        // errdefer while (i != 0) : (i -= 1) paging.kernelPageDirectory.freeVirt(last_page - (i - 1) * PAGE_SIZE) catch @panic("Free failed inside alloc failure");
        errdefer @panic("Kernel stack allocation failure");
        const allocated = try paging.pageAllocator.alloc();
        const v_addr = last_page - i * PAGE_SIZE;
        try paging.kernelPageDirectory.mapVirtToPhy(v_addr, allocated, paging.WRITE);
        try user_pd.mapVirtToPhy(v_addr, allocated, paging.WRITE); // Notice the absence of the USER flag
    }
    return last_page + PAGE_SIZE;
}

/// Frees a kernel stack. Takes size of the stack in pages.
pub fn freeKstack(addr: usize, stack_size: usize) void {
    const last_page = addr - PAGE_SIZE;
    const first_page = addr - PAGE_SIZE * stack_size + 1;
    var i: usize = 0;
    while (i < stack_size) : (i += 1) {
        paging.kernelPageDirectory.freeVirt(last_page - i * PAGE_SIZE) catch unreachable;
    }
    vmemManager.free(first_page);
}
