const std = @import("std");
const paging = @import("paging.zig");
const vmem = @import("vmem.zig");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const PageAllocator = @import("page_allocator.zig").PageAllocator;
const VMemManager = vmem.VMemManager;
const VirtualAllocator = vmem.VirtualAllocator;

var vmemManager = VMemManager{};
var virtualAllocator = VirtualAllocator{ .vmem = &vmemManager };
var generalPurposeAllocator: GeneralPurposeAllocator(.{}) = GeneralPurposeAllocator(.{}){ .backing_allocator = &virtualAllocator.allocator };
pub const allocator: *Allocator = &generalPurposeAllocator.allocator;

pub fn init(size: usize) void {
    paging.init(size / 4);
    vmemManager.init();
}
