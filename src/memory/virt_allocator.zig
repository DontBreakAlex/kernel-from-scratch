const std = @import("std");
const NODE_COUNT: usize = 1024;
const PAGE_SIZE = @import("../memory.zig").PAGE_SIZE;

/// Represent a block of virtual memory
const Block = packed struct {
    /// Begining address (always page-aligned)
    addr: usize,
    /// Size of block (in pages)
    size: usize,
};

const List = std.SinglyLinkedList(Block);
const Node = List.Node;

var nodes: [NODE_COUNT]Node = [_]Node{
    .next = null,
    .data = Block{
        .addr = 0,
        .size = 0,
    },
} ** NODE_COUNT;

var availableNodes = NODE_COUNT;
var lastFreedNode = &nodes[1];

fn allocNode() !*Node {
    if (availableNodes == 0) return error.OutOfMemory;
    if (lastFreedNode) |node| {
        defer lastFreedNode = null;
        availableNodes -= 1;
        return node;
    }
    // TODO: Start search where last node was allocated
    for (nodes) |*node| {
        if (node.data.size == 0) {
            availableNodes -= 1;
            return node;
        }
    }
    return error.OutOfMemory;
}

fn freeNode(node: *Node) void {
    availableNodes += 1;
    lastFreedNode = node;
    node.data.size = 0;
}

var available = List{};
var allocated = List{};

pub fn init() void {
    available.prepend(&nodes[0]);
    nodes[0].data.addr = 0x1000000;
    nodes[0].data.size = 0xc0000000 / PAGE_SIZE;
}

fn insertAvailable(node: *Node) void {
    if (available.first == null) {
        available.first = node;
        return;
    }
    var current: *Node = available.first.?;
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

pub fn alloc(count: usize) !usize {
    var previous: ?*Node = null;
    var current: *Node = available.first.?;
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
        p.removeNext();
    } else {
        available.first = current.next;
        current.next = null;
    }
    if (current.data.size - count != 0) {
        var new_block = try allocNode();
        new_block.data.size = current.data.size - count;
        new_block.data.addr = current.data.addr + count * PAGE_SIZE;
        current.data.size = count;
        insertAvailable(new_block);
    }
    allocated.prepend(current);
    return current.data.addr;
}

pub fn free(addr: usize) void {
    // TODO: Defragment
    var previous: ?*Node = null;
    var current: ?*Node = allocated.first;
    while (current) |c| : (current = current.?.next) {
        if (c.data.addr == addr) {
            if (previous) |p| {
                p.removeNext();
            } else {
                allocated.first = current.next;
            }
            insertAvailable(c);
        }
        previous = current;
    }
}
