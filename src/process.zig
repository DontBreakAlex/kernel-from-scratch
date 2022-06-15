const std = @import("std");
const mem = @import("memory/mem.zig");
const vmem = @import("memory/vmem.zig");
const serial = @import("serial.zig");
const paging = @import("memory/paging.zig");
const scheduler = @import("scheduler.zig");
const dirent = @import("io/dirent.zig");
const fs = @import("io/fs.zig");
const gdt = @import("gdt.zig");

pub const FD_COUNT = 8;
pub const US_STACK_BASE = 0x1000000;
pub const KERNEL_STACK_SIZE = 2;

pub const ProcessState = struct {
    cr3: usize,
    esp: usize,
    regs: usize,
};
pub const State = union { SavedState: ProcessState, ExitCode: usize };
pub const Status = enum { Running, Paused, Zombie, Dead, Sleeping };
pub const Signal = enum(u8) { SIGINT = 0 };
pub const Child = Children.Node;
pub const Children = std.SinglyLinkedList(*Process);
pub const SignalQueue = std.fifo.LinearFifo(Signal, .Dynamic); // TODO: Use fixed size
const PageDirectory = paging.PageDirectory;
const DirEnt = dirent.DirEnt;
const File = fs.File;

pub const Process = struct {
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
    fd: [FD_COUNT]?*File,
    cwd: *DirEnt,

    pub fn queueSignal(self: *Process, sig: Signal) !void {
        const ret = try self.signals.writeItem(sig);
        if (self.status == .Sleeping) {
            self.status = .Paused;
            scheduler.queue.writeItem(self) catch @panic("Scheduler failed");
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
                scheduler.wantsToSwitch = true;
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
        scheduler.runningProcess = self;
        asm volatile (
            \\mov %[pd], %%cr3
            \\mov %[new_esp], %%esp
            \\mov %[data], %%ds
            \\iret
            :
            : [new_esp] "r" (self.kstack - 20),
              [pd] "r" (self.state.SavedState.cr3),
              [data] "r" (@as(u16, gdt.USER_DATA | 3)),
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

    const allocator = mem.allocator;

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
        new_process.cwd = self.cwd;
        std.mem.copy(usize, &new_process.handlers, &self.handlers);
        std.mem.copy(?*File, &new_process.fd, &self.fd);
        for (self.fd) |fd|
            if (fd) |file|
                file.dup();
        errdefer for (new_process.fd) |fd|
            if (fd) |file|
                file.close();
        new_process.pd = try self.pd.dup();
        errdefer new_process.pd.deinit();
        new_process.state = State{ .SavedState = ProcessState{ .cr3 = @ptrToInt(new_process.pd.cr3), .esp = undefined, .regs = undefined } };
        new_process.owner_id = 0;
        new_process.vmem = vmem.VMemManager{};
        new_process.vmem.copy_from(&self.vmem);
        new_process.kstack = try mem.allocKstack(KERNEL_STACK_SIZE, new_process.pd);
        errdefer mem.freeKstack(new_process.kstack, KERNEL_STACK_SIZE);
        serial.format("Process with PID {} has PD at 0x{x:0>8}\n", .{ new_process.pid, @ptrToInt(new_process.pd.cr3) });
        serial.format("Kernel stack bottom: 0x{x:0>8}\n", .{new_process.kstack});
        try scheduler.processes.put(new_process.pid, new_process);
        self.childrens.prepend(child);
        new_process.parent = self;
        return new_process;
    }

    pub fn deinit(self: *Process) void {
        _ = scheduler.processes.remove(self.pid);
        self.signals.deinit();
        self.pd.deinit();
        mem.freeKstack(self.kstack, KERNEL_STACK_SIZE);
        for (self.fd) |fd|
            if (fd) |file|
                file.close();
        allocator.destroy(self);
    }

    pub fn getAvailableFd(self: *Process) !usize {
        for (self.fd) |fd, i| {
            if (fd == null) {
                return i;
            }
        }
        return error.NoFd;
    }
};

var currentPid: u16 = 1;
pub fn getNewPid() u16 {
    defer currentPid += 1;
    return currentPid;
}
