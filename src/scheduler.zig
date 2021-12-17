const std = @import("std");
const paging = @import("memory/paging.zig");
const PageDirectory = paging.PageDirectory;
const allocator = @import("memory/mem.zig").allocator;
const vmem = @import("memory/vmem.zig");
const Signal = enum {
    SIGINT
};
const SignalQueue = std.fifo.LinearFifo(Signals, .Dynamic); // TODO: Use fixed size
const Status = enum { Running, Paused, Zombie, Dead };

const Process = struct {
    pid: u16,
    status: Status,
    parent: ?*Process,
    childrens: []*Process,
    signals: SignalQueue,
    stack_base: usize,
    cr3: PageDirectory,
    owner_id: u16,
    vmem: vmem.VMemManager,

    pub fn queueSignal(self: *Process, sig: Signal) !void {
        return self.signals.writeItem(sig);
    }

    pub fn pipe(self: *Process) !void {
        unreachable;
    }
};

const ProcessList = std.SinglyLinkedList(Process);
const ProcessNode = ProcessList.Node;
const Fn = fn () void;

const processes = ProcessList {};

fn getNewPid() u16 {
    if (processes.first) |p| {
        return p.data.pid + 1;
    }
    return 1;
}

pub fn startProcess(func: Fn) !void {
    const node: *ProcessNode = allocator.create(ProcessNode);
    const process = &node.data;
    process.pid = 0;
    process.status = .Paused;
    process.childrens = []*Process{};
    process.signals = SignalQueue.init(allocator);
    process.stack_base = 0;
    process.cr3 = PageDirectory.init();
    process.owner_id = 0;
    process.vmem = vmem.VMemManager{};
    process.vmem.init();
}