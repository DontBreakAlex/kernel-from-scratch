const std = @import("std");
const paging = @import("memory/paging.zig");
const PageDirectory = paging.PageDirectory;
const allocator = @import("memory/mem.zig").allocator;
const vmem = @import("memory/vmem.zig");
const Signal = enum { SIGINT };
const SignalQueue = std.fifo.LinearFifo(Signal, .Dynamic); // TODO: Use fixed size
const Status = enum { Running, Paused, Zombie, Dead };
const Children = std.SinglyLinkedList(*Process);
const Child = Children.Node;
const US_STACK_BASE = 0x1000000;

const Process = struct {
    pid: u16,
    status: Status,
    parent: ?*Process,
    childrens: Children,
    signals: SignalQueue,
    cr3: usize,
    // Virt addr
    esp: usize,
    // Phy addr
    kstack: usize,
    pd: PageDirectory,
    owner_id: u16,
    vmem: vmem.VMemManager,

    fn queueSignal(self: *Process, sig: Signal) !void {
        return self.signals.writeItem(sig);
    }

    pub fn restore(self: *Process) void {
        runningProcess = self;
        asm volatile (
            \\mov %[pd], %%cr3
            \\mov %[new_esp], %%esp
            \\popa
            \\iret
            :
            : [new_esp] "r" (self.esp),
              [pd] "r" (self.cr3),
            : "memory"
        );
    }

    pub fn runFromFork(self: *Process, frame: usize) void {
        runningProcess = self;
        asm volatile (
            \\mov %[pd], %%cr3
            \\mov %[new_esp], %%esp
            \\fxrstor (%%esp)
            \\mov %[frame], %%esp
            \\popa
            \\iret
            :
            : [new_esp] "r" (self.esp),
              [pd] "r" (self.cr3),
              [frame] "r" (frame),
            : "memory"
        );
    }

    pub fn run(self: *Process) void {
        runningProcess = self;
        asm volatile (
            \\mov %[pd], %%cr3
            \\mov %[new_esp], %%esp
            \\iret
            :
            : [new_esp] "r" (self.esp),
              [pd] "r" (self.cr3),
            : "memory"
        );
    }

    pub fn allocPages(self: *Process, page_count: usize) !usize {
        const v_addr = try self.vmem.alloc(page_count);
        var i: usize = 0;
        while (i < page_count) {
            self.pd.allocVirt(v_addr + paging.PAGE_SIZE * i, paging.WRITE) catch return error.OutOfMemory;
            i += 1;
        }
        return v_addr;
    }

    /// Clones the process. Esp is not copied and must be set manually.
    pub fn clone(self: *Process) !*ProcessNode {
        var new_process_node: *ProcessNode = try allocator.create(ProcessNode);
        var new_process: *Process = &new_process_node.data;
        new_process.pid = getNewPid();
        new_process.status = .Paused;
        new_process.childrens = Children{};
        new_process.signals = SignalQueue.init(allocator);
        new_process.pd = try self.pd.dup();
        new_process.cr3 = @ptrToInt(new_process.pd.cr3);
        new_process.owner_id = 0;
        new_process.vmem = vmem.VMemManager{};
        new_process.vmem.copy_from(&self.vmem);
        new_process.kstack = try paging.pageAllocator.alloc();
        try paging.kernelPageDirectory.mapOneToOne(new_process.kstack);
        new_process.kstack += paging.PAGE_SIZE;
        return new_process_node;
    }
};

const ProcessList = std.SinglyLinkedList(Process);
const ProcessNode = ProcessList.Node;
const Fn = fn () void;

var processes = ProcessList{};
var currentPid: u16 = 1;
pub var runningProcess: *Process = undefined;

fn getNewPid() u16 {
    defer currentPid += 1;
    return currentPid;
}

const vga = @import("vga.zig");
const utils = @import("utils.zig");

pub fn startProcess(func: Fn) !void {
    const node: *ProcessNode = try allocator.create(ProcessNode);
    const process: *Process = &node.data;
    process.pid = getNewPid();
    process.status = .Running;
    process.childrens = Children{};
    process.signals = SignalQueue.init(allocator);
    process.pd = try PageDirectory.init();
    process.cr3 = @ptrToInt(process.pd.cr3);
    process.esp = US_STACK_BASE;
    process.owner_id = 0;
    process.vmem = vmem.VMemManager{};
    process.vmem.init();
    processes.prepend(node);

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try process.pd.mapOneToOne(paging.PAGE_SIZE * i);
    }
    process.kstack = try paging.pageAllocator.alloc();
    try paging.kernelPageDirectory.mapOneToOne(process.kstack);
    process.kstack += paging.PAGE_SIZE;
    var esp = try paging.pageAllocator.alloc();
    try paging.kernelPageDirectory.mapOneToOne(esp);
    try process.pd.mapVirtToPhy(process.esp - paging.PAGE_SIZE, esp, paging.WRITE);
    process.esp -= 44;
    esp += 4092;
    @intToPtr(*usize, esp).* = 0x202; // eflags
    esp -= 4;
    @intToPtr(*usize, esp).* = 0x8; // cs
    esp -= 4;
    @intToPtr(*usize, esp).* = @ptrToInt(func); // eip
    // utils.boch_break();
    process.restore();
}