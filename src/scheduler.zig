const std = @import("std");
const paging = @import("memory/paging.zig");
const PageDirectory = paging.PageDirectory;
const allocator = @import("memory/mem.zig").allocator;
const vmem = @import("memory/vmem.zig");
const Signal = enum { SIGINT };
const SignalQueue = std.fifo.LinearFifo(Signal, .Dynamic); // TODO: Use fixed size
const Status = enum { Running, Paused, Zombie, Dead };

const Process = struct {
    pid: u16,
    status: Status,
    parent: ?*Process,
    // childrens: []*Process,
    signals: SignalQueue,
    esp: usize,
    cr3: PageDirectory,
    owner_id: u16,
    vmem: vmem.VMemManager,

    pub fn queueSignal(self: *Process, sig: Signal) !void {
        return self.signals.writeItem(sig);
    }

    // pub fn pipe(self: *Process) !void {
    //     unreachable;
    // }
};

const ProcessList = std.SinglyLinkedList(Process);
const ProcessNode = ProcessList.Node;
const Fn = fn () void;

var processes = ProcessList{};
var currentPid: u16 = 1;

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
    // process.childrens = []*Process{};
    process.signals = SignalQueue.init(allocator);
    process.esp = 0x1000000;
    process.cr3 = try PageDirectory.init();
    process.owner_id = 0;
    process.vmem = vmem.VMemManager{};
    process.vmem.init();
    processes.prepend(node);

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try process.cr3.mapOneToOne(0x1000 * i);
    }
    var esp = try paging.pageAllocator.alloc();
    try paging.kernelPageDirectory.mapOneToOne(esp);
    try process.cr3.mapVirtToPhy(process.esp - 0x1000, esp, paging.WRITE);
    process.esp -= 12;
    esp += 4092;
    @intToPtr(*usize, esp).* = 0x202; // eflags
    esp -= 4;
    @intToPtr(*usize, esp).* = 0x8; // cs
    esp -= 4;
    @intToPtr(*usize, esp).* = @ptrToInt(func); // eip
    asm volatile (
        \\xchg %%bx, %%bx
        \\mov %[pd], %%cr3
        \\mov %[new_esp], %%esp
        \\iret
        :
        : [new_esp] "r" (process.esp),
          [pd] "r" (process.cr3.cr3),
        : "memory"
    );
}
