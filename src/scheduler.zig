const std = @import("std");
const paging = @import("memory/paging.zig");
const PageDirectory = paging.PageDirectory;
const mem = @import("memory/mem.zig");
const allocator = mem.allocator;
const vmem = @import("memory/vmem.zig");
pub const Signal = enum(u8) { SIGINT = 0 };
const SignalQueue = std.fifo.LinearFifo(Signal, .Dynamic); // TODO: Use fixed size
const Children = std.SinglyLinkedList(*Process);
const Child = Children.Node;
const US_STACK_BASE = 0x1000000;
const KERNEL_STACK_SIZE = 2;
const Buffer = utils.Buffer;
const keyboard = @import("keyboard.zig");
const serial = @import("serial.zig");

pub var wantsToSwitch: bool = false;
pub var canSwitch: bool = true;

pub const Status = enum { Running, Paused, Zombie, Dead, IO };

const Process = struct {
    pid: u16,
    status: Status,
    parent: ?*Process,
    childrens: Children,
    signals: SignalQueue,
    handlers: [1]usize,
    cr3: usize,
    // Virt addr
    esp: usize,
    regs: usize,
    // Phy addr
    kstack: usize,
    pd: PageDirectory,
    owner_id: u16,
    vmem: vmem.VMemManager,
    fd: [128]?*Buffer,

    pub fn queueSignal(self: *Process, sig: Signal) !void {
        return self.signals.writeItem(sig);
    }

    pub fn setSigHanlder(self: *Process, sig: Signal, handler: usize) usize {
        const old = self.handlers[@enumToInt(sig)];
        self.handlers[@enumToInt(sig)] = handler;
        return old;
    }

    /// Saves a process. Does not update current process.
    pub fn save(self: *Process, esp: usize, regs: usize, cr3: usize) void {
        self.cr3 = cr3;
        self.esp = esp;
        self.regs = regs;
    }

    /// Resume the process. Does not update current process.
    pub fn restore(self: *Process) void {
        asm volatile (
            \\mov %[pd], %%cr3
            \\mov %[new_esp], %%esp
            \\fxrstor (%%esp)
            \\mov %[regs], %%esp
            \\popa
            \\iret
            :
            : [new_esp] "r" (self.esp),
              [pd] "r" (self.cr3),
              [regs] "r" (self.regs),
            : "memory"
        );
    }

    pub fn start(self: *Process) void {
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
            // TODO: De-alloc already allocated pages on failure (or do lazy alloc)
            self.pd.allocVirt(v_addr + paging.PAGE_SIZE * i, paging.WRITE) catch return error.OutOfMemory;
            i += 1;
        }
        return v_addr;
    }

    pub fn deallocPages(self: *Process, v_addr: usize, page_count: usize) void {
        self.vmem.free(v_addr);
        var i: usize = 0;
        while (i < page_count) : (i += 1) {
            self.pd.freeVirt(v_addr + paging.PAGE_SIZE * i) catch unreachable;
        }
    }

    /// Clones the process. Esp is not copied and must be set manually.
    pub fn clone(self: *Process) !*Process {
        // TODO: Copy fds
        var new_process: *Process = try allocator.create(Process);
        errdefer allocator.destroy(new_process);
        const child: *Child = try allocator.create(Child);
        errdefer allocator.destroy(child);
        child.data = new_process;
        new_process.pid = getNewPid();
        new_process.status = .Paused;
        new_process.childrens = Children{};
        new_process.signals = SignalQueue.init(allocator);
        std.mem.copy(usize, &new_process.handlers, &self.handlers);
        new_process.pd = try self.pd.dup();
        new_process.cr3 = @ptrToInt(new_process.pd.cr3);
        new_process.owner_id = 0;
        new_process.vmem = vmem.VMemManager{};
        new_process.vmem.copy_from(&self.vmem);
        new_process.kstack = try mem.allocKstack(KERNEL_STACK_SIZE);
        self.childrens.prepend(child);
        return new_process;
    }

    pub fn deinit(self: *Process) void {
        // TODO: Dealloc stacks
        self.signals.deinit();
        self.pd.deinit();
        mem.freeKstack(self.kstack, KERNEL_STACK_SIZE);
        allocator.destroy(self);
    }
};

const ProcessQueue = std.fifo.LinearFifo(*Process, .Dynamic);
const EventList = std.ArrayListUnmanaged(*Process);
const Events = std.AutoHashMap(*Buffer, EventList);
const Fn = fn () void;

pub var queue: ProcessQueue = ProcessQueue.init(allocator);
pub var events: Events = Events.init(allocator);
var currentPid: u16 = 1;
pub var runningProcess: *Process = undefined;

fn getNewPid() u16 {
    defer currentPid += 1;
    return currentPid;
}

const vga = @import("vga.zig");
const utils = @import("utils.zig");

pub fn startProcess(func: Fn) !void {
    const process: *Process = try allocator.create(Process);
    process.pid = getNewPid();
    process.status = .Running;
    process.childrens = Children{};
    process.signals = SignalQueue.init(allocator);
    process.handlers = .{0} ** 1;
    process.pd = try PageDirectory.init();
    process.cr3 = @ptrToInt(process.pd.cr3);
    process.esp = US_STACK_BASE;
    process.owner_id = 0;
    process.vmem = vmem.VMemManager{};
    process.vmem.init();
    process.fd = .{null} ** 128;
    process.fd[0] = &keyboard.queue;

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try process.pd.mapOneToOne(paging.PAGE_SIZE * i);
    }
    paging.printDirectory(process.pd.cr3);
    process.kstack = try mem.allocKstack(2);
    serial.format("Kernel stack bottom: 0x{x:0>8}\n", .{process.kstack});
    var esp = try paging.pageAllocator.alloc();
    try paging.kernelPageDirectory.mapOneToOne(esp);
    try process.pd.mapVirtToPhy(process.esp - paging.PAGE_SIZE, esp, paging.WRITE);
    process.esp -= 12;
    esp += 4092;
    @intToPtr(*usize, esp).* = 0x202; // eflags
    esp -= 4;
    @intToPtr(*usize, esp).* = 0x8; // cs
    esp -= 4;
    @intToPtr(*usize, esp).* = @ptrToInt(func); // eip
    // utils.boch_break();
    process.start();
}

pub export fn schedule(esp: usize, regs: usize, cr3: usize) callconv(.C) void {
    canSwitch = false;
    switch (runningProcess.status) {
        .IO => {
            while (queue.count == 0)
                asm volatile (
                    \\sti
                    \\hlt
                );
            runningProcess.save(esp, regs, cr3);
            runningProcess = queue.readItem() orelse @panic("Scheduler failed");
        },
        .Running => {
            if (queue.count == 0) return;
            runningProcess.status = .Paused;
            runningProcess.save(esp, regs, cr3);
            queue.writeItem(runningProcess) catch @panic("Scheduler failed");
            runningProcess = queue.readItem() orelse @panic("Scheduler failed");
        },
        .Zombie => {
            while (queue.count == 0) {
                if (events.count() == 0)
                    @panic("Attempt to kill last process !");
                asm volatile (
                    \\sti
                    \\hlt
                );
            }
            runningProcess = queue.readItem() orelse @panic("Scheduler failed");
        },
        else => @panic("Scheduler interupted non-running process (?!)"),
    }
    runningProcess.status = .Running;
    canSwitch = true;
    runningProcess.restore();
}

pub fn queueEvent(key: *Buffer, val: *Process) !void {
    var res = try events.getOrPut(key);
    var array: *EventList = res.value_ptr;
    if (!res.found_existing)
        array.* = EventList{};
    try array.append(allocator, val);
}

pub fn writeWithEvent(buffer: *Buffer, data: []const u8) !void {
    if (events.getPtr(buffer)) |array| {
        try queue.ensureUnusedCapacity(array.items.len);
        try buffer.write(data);
        queue.writeAssumeCapacity(array.items);
        array.clearRetainingCapacity();
    } else {
        try buffer.write(data);
    }
}
