const std = @import("std");
const utils = @import("../utils.zig");
const paging = @import("paging.zig");
const NODE_COUNT: usize = 1024;
const PAGE_SIZE = paging.PAGE_SIZE;
const PRESENT = paging.PRESENT;
const WRITE = paging.WRITE;
const Allocator = std.mem.Allocator;

pub const VMemManager = struct {
    /// Represent a block of virtual memory
    const Block = packed struct {
        /// Begining address (always page-aligned)
        addr: usize,
        /// Size of block (in pages)
        size: usize,
    };
    const List = std.SinglyLinkedList(Block);
    const Node = List.Node;

    nodes: [NODE_COUNT]Node = [_]Node{Node{
        .next = null,
        .data = Block{
            .addr = 0,
            .size = 0,
        },
    }} ** NODE_COUNT,
    availableNodes: usize = NODE_COUNT,
    lastFreedNode: ?*Node = null,
    available: List = List{},
    allocated: List = List{},

    fn allocNode(self: *VMemManager) !*Node {
        if (self.availableNodes == 0) return error.OutOfMemory;
        if (self.lastFreedNode) |node| {
            defer self.lastFreedNode = null;
            self.availableNodes -= 1;
            return node;
        }
        // TODO: Start search where last node was allocated
        for (self.nodes) |*node| {
            if (node.data.size == 0) {
                self.availableNodes -= 1;
                return node;
            }
        }
        return error.OutOfMemory;
    }

    fn freeNode(self: *VMemManager, node: *Node) void {
        self.availableNodes += 1;
        self.lastFreedNode = node;
        node.data.size = 0;
    }

    pub fn init(self: *VMemManager) void {
        self.available.prepend(&self.nodes[0]);
        self.nodes[0].data.addr = 0x1000000;
        self.nodes[0].data.size = 0xc0000000 / PAGE_SIZE;
        self.lastFreedNode = &self.nodes[1];
    }

    fn insertAvailable(self: *VMemManager, node: *Node) void {
        if (self.available.first == null) {
            self.available.first = node;
            return;
        }
        var current: *Node = self.available.first.?;
        var next: ?*Node = current.next;
        while (next) |n| {
            if (n.data.size < node.data.size)
                break;
            current = n;
            next = current.next;
        }
        current.next = node;
        node.next = next;
    }

    pub fn alloc(self: *VMemManager, count: usize) !usize {
        var previous: ?*Node = null;
        var current: *Node = self.available.first.?;
        var next: ?*Node = current.next;
        while (next) |n| {
            if (n.data.size < count)
                break;
            previous = current;
            current = n;
            next = current.next;
        }
        if (current.data.size < count) return error.OutOfMemory;
        if (previous) |p| {
            _ = p.removeNext();
        } else {
            self.available.first = current.next;
            current.next = null;
        }
        if (current.data.size - count != 0) {
            var new_block = try self.allocNode();
            new_block.data.size = current.data.size - count;
            new_block.data.addr = current.data.addr + count * PAGE_SIZE;
            current.data.size = count;
            self.insertAvailable(new_block);
        }
        self.allocated.prepend(current);
        return current.data.addr;
    }

    pub fn free(self: *VMemManager, addr: usize) void {
        // TODO: Defragment
        var previous: ?*Node = null;
        var current: ?*Node = self.allocated.first;
        while (current) |c| : (current = current.?.next) {
            if (c.data.addr == addr) {
                if (previous) |p| {
                    _ = p.removeNext();
                } else {
                    self.allocated.first = c.next;
                }
                self.insertAvailable(c);
                break;
            }
            previous = current;
        }
    }
};

pub const VirtualAllocator = struct {
    allocator: Allocator = Allocator{
        .resizeFn = resizeFn,
        .allocFn = allocFn,
    },
    vmem: *VMemManager,

    fn allocFn(field: *Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
        _ = ret_addr;
        const self = @fieldParentPtr(VirtualAllocator, "allocator", field);
        if (ptr_align > PAGE_SIZE)
            @panic("Unsuported aligned virtual alloc");
        const page_count = utils.divCeil(len, PAGE_SIZE);
        const v_addr = try self.vmem.alloc(page_count);
        var i: usize = 0;
        var addr = v_addr;
        while (i < page_count) {
            paging.allocVirt(addr, WRITE) catch return Allocator.Error.OutOfMemory;
            i += 1;
            addr += PAGE_SIZE;
        }
        const requested_len = std.mem.alignAllocLen(page_count * PAGE_SIZE, len, len_align);
        return @intToPtr([*]u8, v_addr)[0..requested_len];
    }

    fn resizeFn(field: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) !usize {
        _ = buf_align;
        _ = len_align;
        _ = ret_addr;
        if (new_len != 0)
            @panic("Attempt to resize virtual alloc");
        const self = @fieldParentPtr(VirtualAllocator, "allocator", field);
        self.vmem.free(@ptrToInt(buf.ptr));
        var i = utils.divCeil(buf.len, PAGE_SIZE);
        var addr = @ptrToInt(buf.ptr);
        while (i != 0) {
            paging.unMap(addr);
            i -= 1;
            addr += PAGE_SIZE;
        }
        return 0;
    }
};
