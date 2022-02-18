const std = @import("std");
const paging = @import("memory/paging.zig");
const PageDirectory = paging.PageDirectory;
const mem = @import("memory/mem.zig");
const allocator = mem.allocator;
const vmem = @import("memory/vmem.zig");
pub const Signal = enum(u8) { SIGINT = 0 };
const SignalQueue = std.fifo.LinearFifo(Signal, .Dynamic); // TODO: Use fixed size
const Children = std.SinglyLinkedList(*Process);
pub const Child = Children.Node;
const US_STACK_BASE = 0x1000000;
const KERNEL_STACK_SIZE = 2;
const FD_COUNT = 4;
const Buffer = utils.Buffer;
const keyboard = @import("keyboard.zig");
const serial = @import("serial.zig");
const FileDescriptor = @import("file_descriptor.zig").FileDescriptor;

pub var wantsToSwitch: bool = false;
pub var canSwitch: bool = true;

pub const ProcessState = struct {
    cr3: usize,
    esp: usize,
    regs: usize,
};
pub const State = union { SavedState: ProcessState, ExitCode: usize };
pub const Status = enum { Running, Paused, Zombie, Dead, Sleeping };

const Process = struct {
    pid: u16,
    status: Status,
    parent: ?*Process,
    childrens: Children,
    signals: SignalQueue,
    handlers: [1]usize,
    state: State,
    // Phy addr
    kstack: usize,
    pd: PageDirectory,
    owner_id: u16,
    vmem: vmem.VMemManager,
    fd: [FD_COUNT]FileDescriptor,

    pub fn queueSignal(self: *Process, sig: Signal) !void {
        const ret = try self.signals.writeItem(sig);
        if (self.status == .Sleeping) {
            self.status = .Paused;
            queue.writeItem(self) catch @panic("Scheduler failed");
        }
        return ret;
    }

    pub fn setSigHanlder(self: *Process, sig: Signal, handler: usize) usize {
        const old = self.handlers[@enumToInt(sig)];
        self.handlers[@enumToInt(sig)] = handler;
        return old;
    }

    /// Saves a process. Does not update current process.
    pub fn save(self: *Process, esp: usize, regs: usize, cr3: usize) void {
        self.state = State{ .SavedState = ProcessState{ .cr3 = cr3, .esp = esp, .regs = regs } };
    }

    /// Resume the process. Does not update current process.
    pub fn restore(self: *Process) void {
        // Check if there is a signal to be delivered
        if (self.signals.count != 0) {
            const sig = self.signals.peekItem(0);
            const handler = self.handlers[@enumToInt(sig)];
            // Check if there is a handler for the signal
            if (handler != 0) {
                if (self.state.SavedState.cr3 != @ptrToInt(paging.kernelPageDirectory.cr3)) {
                    // Process is not in a syscall, we can deliver the signal
                    self.signals.discard(1);
                    asm volatile (
                        \\xchg %%bx, %%bx
                        \\mov %[pd], %%cr3
                        \\mov %[new_esp], %%esp
                        \\push %[regs]
                        \\call *%[handler]
                        \\pop %[regs]
                        \\fxrstor (%%esp)
                        \\mov %[regs], %%esp
                        \\popa
                        \\iret
                        :
                        : [new_esp] "r" (self.state.SavedState.esp),
                          [pd] "r" (self.state.SavedState.cr3),
                          [regs] "r" (self.state.SavedState.regs),
                          [handler] "r" (handler),
                        : "memory"
                    );
                }
                // Process is in a syscall, reschedule when the syscall is over to deliver the signal
                wantsToSwitch = true;
            }
        }
        asm volatile (
            \\mov %[pd], %%cr3
            \\mov %[new_esp], %%esp
            \\fxrstor (%%esp)
            \\mov %[regs], %%esp
            \\popa
            \\iret
            :
            : [new_esp] "r" (self.state.SavedState.esp),
              [pd] "r" (self.state.SavedState.cr3),
              [regs] "r" (self.state.SavedState.regs),
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
            : [new_esp] "r" (self.state.SavedState.esp),
              [pd] "r" (self.state.SavedState.cr3),
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
        std.mem.copy(FileDescriptor, &new_process.fd, &self.fd);
        for (self.fd) |*fd|
            fd.dup();
        errdefer for (new_process.fd) |*fd|
            fd.close();
        new_process.pd = try self.pd.dup();
        errdefer new_process.pd.deinit();
        new_process.state = State{ .SavedState = ProcessState{ .cr3 = @ptrToInt(new_process.pd.cr3), .esp = undefined, .regs = undefined } };
        new_process.owner_id = 0;
        new_process.vmem = vmem.VMemManager{};
        new_process.vmem.copy_from(&self.vmem);
        new_process.kstack = try mem.allocKstack(KERNEL_STACK_SIZE);
        errdefer mem.freeKstack(new_process.kstack, KERNEL_STACK_SIZE);
        serial.format("Process with PID {} has PD at 0x{x:0>8}\n", .{ new_process.pid, @ptrToInt(new_process.pd.cr3) });
        serial.format("Kernel stack bottom: 0x{x:0>8}\n", .{new_process.kstack});
        try processes.put(new_process.pid, new_process);
        self.childrens.prepend(child);
        new_process.parent = self;
        return new_process;
    }

    pub fn deinit(self: *Process) void {
        _ = processes.remove(self.pid);
        self.signals.deinit();
        self.pd.deinit();
        mem.freeKstack(self.kstack, KERNEL_STACK_SIZE);
        for (self.fd) |*fd|
            fd.close();
        allocator.destroy(self);
    }

    pub const FileDescriptorAndIndex = struct {
        fd: *FileDescriptor,
        i: u8,
    };

    pub fn getAvailableFd(self: *Process) !FileDescriptorAndIndex {
        for (self.fd) |*descriptor, i| {
            if (descriptor.* == .Closed) {
                return FileDescriptorAndIndex{ .fd = descriptor, .i = @intCast(u8, i) };
            }
        }
        return error.NoFd;
    }
};

const ProcessMap = std.AutoHashMap(u16, *Process);
const ProcessQueue = std.fifo.LinearFifo(*Process, .Dynamic);
const EventList = std.ArrayListUnmanaged(*Process);
const Events = std.AutoHashMap(Event, EventList);
const Fn = fn () void;
pub const Event = union(enum) {
    IO: FileDescriptor,
    CHILD,
};

pub var queue: ProcessQueue = ProcessQueue.init(allocator);
pub var events: Events = Events.init(allocator);
pub var processes: ProcessMap = ProcessMap.init(allocator);
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
    process.state = .{ .SavedState = ProcessState{
        .cr3 = @ptrToInt(process.pd.cr3),
        .esp = US_STACK_BASE,
        .regs = 0,
    } };
    process.owner_id = 0;
    process.vmem = vmem.VMemManager{};
    process.vmem.init();
    process.fd = .{.Closed} ** FD_COUNT;
    process.fd[0] = FileDescriptor{ .SimpleReadable = &keyboard.queue };
    process.parent = null;

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try process.pd.mapOneToOne(paging.PAGE_SIZE * i);
    }
    // paging.printDirectory(process.pd.cr3);
    serial.format("Shell has PD at 0x{x:0>8}\n", .{@ptrToInt(process.pd.cr3)});
    process.kstack = try mem.allocKstack(2);
    serial.format("Kernel stack bottom: 0x{x:0>8}\n", .{process.kstack});
    var esp = try paging.pageAllocator.alloc();
    try process.pd.mapVirtToPhy(process.state.SavedState.esp - paging.PAGE_SIZE, esp, paging.WRITE);
    process.state.SavedState.esp -= 12;
    esp += 4092;
    @intToPtr(*usize, esp).* = 0x202; // eflags
    esp -= 4;
    @intToPtr(*usize, esp).* = 0x8; // cs
    esp -= 4;
    @intToPtr(*usize, esp).* = @ptrToInt(func); // eip
    // utils.boch_break();
    try processes.put(process.pid, process);
    process.start();
}

pub export fn schedule(esp: usize, regs: usize, cr3: usize) callconv(.C) void {
    canSwitch = false;
    switch (runningProcess.status) {
        .Sleeping => {
            while (queue.count == 0)
                asm volatile (
                    \\sti
                    \\hlt
                );
            runningProcess.save(esp, regs, cr3);
            runningProcess = queue.readItem() orelse @panic("Scheduler failed");
        },
        .Running => {
            runningProcess.status = .Paused;
            runningProcess.save(esp, regs, cr3);
            if (queue.count != 0) {
                queue.writeItem(runningProcess) catch @panic("Scheduler failed");
                runningProcess = queue.readItem() orelse @panic("Scheduler failed");
            }
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

pub fn queueEvent(key: Event, val: *Process) !void {
    var res = try events.getOrPut(key);
    var array: *EventList = res.value_ptr;
    if (!res.found_existing)
        array.* = EventList{};
    try array.append(allocator, val);
}

pub fn writeWithEvent(fd: FileDescriptor, src: []const u8) !void {
    if (events.getPtr(Event{ .IO = fd })) |array| {
        try queue.ensureUnusedCapacity(array.items.len);
        try fd.write(src);
        queue.writeAssumeCapacity(array.items);
        array.clearRetainingCapacity();
    } else {
        try fd.write(src);
    }
}

pub fn readWithEvent(fd: FileDescriptor, dst: []u8) !usize {
    var ret: usize = undefined;
    if (events.getPtr(Event{ .IO = fd })) |array| {
        try queue.ensureUnusedCapacity(array.items.len);
        ret = fd.read(dst);
        queue.writeAssumeCapacity(array.items);
        array.clearRetainingCapacity();
    } else {
        ret = fd.read(dst);
    }
    return ret;
}
