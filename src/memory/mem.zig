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

pub fn mapStructure(comptime T: type, ptr: *T, cr3: PageDirectory) !*T {
    const buffer = try mapBuffer(@sizeOf(T), @ptrToInt(ptr), cr3);
    return @intToPtr(*T, @ptrToInt(buffer.ptr));
}

pub fn unMapStructure(comptime T: type, v_addr: *T) !void {
    return unMapBuffer(@sizeOf(T), @ptrToInt(v_addr));
}

pub fn mapBuffer(size: usize, ptr: usize, cr3: PageDirectory) ![]u8 {
    const first_page = std.mem.alignBackward(ptr, PAGE_SIZE);
    const last_page = std.mem.alignBackward(ptr + size, PAGE_SIZE);
    if (first_page == last_page) {
        // Whole buffer is one page
        const p_addr = cr3.virtToPhy(ptr) orelse return error.NotMapped;
        const v_addr = try vmemManager.alloc(1);
        try paging.kernelPageDirectory.mapVirtToPhy(v_addr, p_addr, paging.WRITE);
        return @intToPtr([*]u8, v_addr | (ptr & 0b111111111111))[0..size];
    } else {
        // Buffer spans around multiple pages
        const page_count = (last_page - first_page) / PAGE_SIZE;
        const p_addr = cr3.virtToPhy(ptr) orelse return error.NotMapped;
        const v_addr = try vmemManager.alloc(page_count);
        var i: usize = 0;
        while (i < page_count) : (i += 1) {
            try paging.kernelPageDirectory.mapVirtToPhy(v_addr + PAGE_SIZE * i, p_addr + PAGE_SIZE * i, paging.WRITE);
        }
        return @intToPtr([*]u8, v_addr | (ptr & 0b111111111111))[0..size];
    }
}

pub fn unMapBuffer(size: usize, v_addr: usize) !void {
    const first_page = std.mem.alignBackward(v_addr, PAGE_SIZE);
    const last_page = std.mem.alignBackward(v_addr + size, PAGE_SIZE);
    if (first_page == last_page) {
        _ = try paging.kernelPageDirectory.unMap(first_page);
    } else {
        const page_count = (last_page - first_page) / PAGE_SIZE;
        var i: usize = 0;
        while (i < page_count) : (i += 1) {
            _ = try paging.kernelPageDirectory.unMap(v_addr + PAGE_SIZE * i);
        }
    }
}
