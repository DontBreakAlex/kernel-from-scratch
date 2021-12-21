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

    fn queueSignal(self: *Process, sig: Signal) !void {
        return self.signals.writeItem(sig);
    }

    fn restore(self: *Process) void {
        runningProcess = self;
        asm volatile (
            \\mov %[pd], %%cr3
            \\mov %[new_esp], %%esp
            \\popa
            \\iret
            :
            : [new_esp] "r" (self.esp),
              [pd] "r" (self.cr3.cr3),
            : "memory"
        );
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
