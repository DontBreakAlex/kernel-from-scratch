const std = @import("std");
const paging = @import("memory/paging.zig");
const scheduler = @import("scheduler.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const mem = @import("memory/mem.zig");
const serial = @import("serial.zig");
const file_descriptor = @import("file_descriptor.zig");

const PageDirectory = paging.PageDirectory;
const PageEntry = paging.PageEntry;
const PageAllocator = @import("memory/page_allocator.zig").PageAllocator;
const Event = scheduler.Event;
const Process = scheduler.Process;
const Pipe = file_descriptor.Pipe;
const FileDescriptor = file_descriptor.FileDescriptor;

pub fn init() void {
    idt.setIdtEntry(0x80, @ptrToInt(syscall_handler));
    idt.setIdtEntry(0x81, @ptrToInt(preempt));
}

// TODO: Check cr3 and stack
fn preempt() callconv(.Naked) void {
    asm volatile (
        \\pusha
        \\mov %%esp, %%ebp
        \\sub $512, %%esp
        \\andl $0xFFFFFFF0, %%esp
        \\fxsave (%%esp)
        \\mov %%esp, %%ecx
        \\mov %%cr3, %%ebx
        \\push %%ebx
        \\push %%ebp
        \\push %%ecx
        \\call schedule
    );
    @panic("Schedule returned in preempt");
}

pub fn syscall_handler() callconv(.Naked) void {
    asm volatile (
        \\pusha
        \\mov %%esp, %%ebp
        \\sub $512, %%esp
        \\andl $0xFFFFFFF0, %%esp
        \\fxsave (%%esp)
        ::: "ebp");
    asm volatile (
        \\mov %%cr3, %%ecx
        \\mov %%esp, %%edx
        \\mov %[new_cr3], %%cr3
        \\mov (%[new_stack]), %%esp
        \\push %%edx
        \\push %%ecx
        \\push %%ebp
        \\call syscallHandlerInKS
        \\add $4, %%esp
        \\pop %%ecx
        \\pop %%edx
        \\mov %%ecx, %%cr3
        \\mov %%edx, %%esp
        \\fxrstor (%%esp)
        \\mov %%ebp, %%esp
        \\popa
        \\iret
        :
        : [new_cr3] "r" (paging.kernelPageDirectory.cr3),
          [new_stack] "r" (&scheduler.runningProcess.kstack),
        : "ebp", "ecx", "edx"
    );
}

// eax: Syscall number
// ebx: arg1
// ecx: arg2
// edx: arg3
// esi: arg4
// edi: arg5
// ebp: arg6

export fn syscallHandlerInKS(regs_ptr: *idt.Regs, u_cr3: *[1024]PageEntry, us_esp: usize) callconv(.C) void {
    const PD = PageDirectory{ .cr3 = u_cr3 };
    scheduler.canSwitch = false;
    const regs = PD.vPtrToPhy(idt.Regs, regs_ptr) catch |err| {
        vga.format("{}\n", .{err});
        @panic("Syscall failure");
    };
    scheduler.canSwitch = true;
    @setRuntimeSafety(false);
    regs.eax = @bitCast(usize, switch (regs.eax) {
        1 => exit(regs.ebx),
        2 => fork(regs_ptr, us_esp) catch -1,
        3 => read(regs.ebx, regs.ecx, regs.edx),
        4 => write(regs.ebx, regs.ecx, regs.edx),
        6 => close(regs.ebx),
        7 => waitpid(),
        9 => mmap(regs.ebx),
        11 => munmap(regs.ebx, regs.ecx),
        20 => getpid(),
        37 => kill(regs.ebx, regs.ecx),
        42 => pipe(regs.ebx) catch -1,
        48 => signal(regs.ebx, regs.ecx),
        102 => getuid(),
        162 => sleep(),
        177 => sigwait(),
        222 => usage(regs.ebx) catch -1,
        else => {
            @panic("Unhandled syscall");
        },
    });
    // TODO: Try to reuse maps
    if (scheduler.wantsToSwitch) {
        scheduler.wantsToSwitch = false;
        scheduler.schedule(us_esp, @ptrToInt(regs_ptr), @ptrToInt(u_cr3));
    }
}

fn mmap(count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    return @intCast(isize, scheduler.runningProcess.allocPages(count) catch std.math.maxInt(usize));
}

fn munmap(addr: usize, count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    scheduler.runningProcess.deallocPages(addr, count);
    return 0;
}

fn getpid() isize {
    return scheduler.runningProcess.pid;
}

fn getuid() isize {
    return scheduler.runningProcess.owner_id;
}

fn fork(regs_ptr: *idt.Regs, us_esp: usize) !isize {
    const new_process = try scheduler.runningProcess.clone();
    errdefer new_process.deinit();
    new_process.state.SavedState.esp = us_esp;
    new_process.state.SavedState.regs = @ptrToInt(regs_ptr);
    scheduler.canSwitch = false;
    {
        const regs = try new_process.pd.vPtrToPhy(idt.Regs, regs_ptr);
        vga.putPtr(@ptrToInt(regs));
        utils.boch_break();
        regs.eax = 0;
    }
    try scheduler.queue.writeItem(new_process);
    scheduler.canSwitch = true;
    return new_process.pid;
}

fn sleep() isize {
    if (!scheduler.canSwitch)
        unreachable;
    scheduler.wantsToSwitch = true;
    return 0;
}

fn signal(sig: usize, handler: usize) isize {
    return @bitCast(isize, scheduler.runningProcess.setSigHanlder(@intToEnum(scheduler.Signal, @truncate(u8, sig)), handler));
}

fn read(fd: usize, buff: usize, count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    const descriptor = scheduler.runningProcess.fd[fd];
    if (descriptor != .Closed) {
        if (!descriptor.isReadable())
            return -1;
        while (descriptor.readableLength() == 0) {
            scheduler.queueEvent(descriptor.event(), scheduler.runningProcess) catch return -1;
            scheduler.runningProcess.status = .Sleeping;
            scheduler.canSwitch = true;
            asm volatile ("int $0x81");
            scheduler.canSwitch = false;
        }
        var user_buf = scheduler.runningProcess.pd.vBufferToPhy(count, buff) catch return -1;
        return @intCast(isize, scheduler.readWithEvent(descriptor, user_buf) catch return -1);
    }
    return -1;
}

fn write(fd: usize, buff: usize, count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    const descriptor = scheduler.runningProcess.fd[fd];
    if (descriptor != .Closed) {
        if (!descriptor.isWritable())
            return -1;
        while (descriptor.writableLength() == 0) {
            scheduler.queueEvent(descriptor.event(), scheduler.runningProcess) catch return -1;
            scheduler.runningProcess.status = .Sleeping;
            scheduler.canSwitch = true;
            asm volatile ("int $0x81");
            scheduler.canSwitch = false;
        }
        var user_buf = scheduler.runningProcess.pd.vBufferToPhy(count, buff) catch return -1;
        const to_write = std.math.min(descriptor.writableLength(), count);
        scheduler.writeWithEvent(descriptor, user_buf[0..to_write]) catch return -1;
        return @intCast(isize, to_write);
    }
    return -1;
}

fn exit(code: usize) isize {
    scheduler.canSwitch = false;
    scheduler.runningProcess.status = .Zombie;
    scheduler.runningProcess.state = .{ .ExitCode = code };
    if (scheduler.runningProcess.parent) |parent| {
        if (parent.status == .Sleeping) {
            parent.status = .Paused;
            scheduler.queue.writeItem(parent) catch @panic("Alloc failure in exit");
        }
    } else @panic("Init process exited");
    scheduler.canSwitch = true;
    scheduler.schedule(undefined, undefined, undefined);
    return 0;
}

fn usage(u_ptr: usize) !isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    var u_struct = try scheduler.runningProcess.pd.vPtrToPhy(PageAllocator.AllocatorUsage, @intToPtr(*PageAllocator.AllocatorUsage, u_ptr));
    u_struct.* = paging.pageAllocator.usage();
    return 0;
}

fn waitpid() isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    var child = scheduler.runningProcess.childrens.first;
    var prev: ?*scheduler.Child = null;
    while (true) {
        scheduler.runningProcess.status = .Sleeping;
        scheduler.canSwitch = true;
        asm volatile ("int $0x81");
        scheduler.canSwitch = false;
        while (child) |c| {
            if (c.data.status == .Zombie) {
                const pid = c.data.pid;
                _ = if (prev) |p|
                    p.removeNext()
                else
                    scheduler.runningProcess.childrens.popFirst();
                c.data.deinit();
                return @intCast(isize, pid);
            }
            prev = c;
            child = c.next;
        }
    }
    return -1;
}

fn kill(pid: usize, sig: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    const process = scheduler.processes.get(@intCast(u16, pid)) orelse return -1;
    process.queueSignal(@intToEnum(scheduler.Signal, sig)) catch return -1;
    return 0;
}

fn sigwait() isize {
    if (!scheduler.canSwitch)
        unreachable;
    scheduler.runningProcess.status = .Sleeping;
    scheduler.wantsToSwitch = true;
    return 0;
}

fn pipe(us_fds: usize) !isize {
    const new_pipe: *Pipe = try mem.allocator.create(Pipe);
    const ks_fds = try scheduler.runningProcess.pd.vPtrToPhy([2]usize, @intToPtr(*[2]usize, us_fds));
    const fd_out = try scheduler.runningProcess.getAvailableFd();
    fd_out.fd.* = .{ .PipeOut = new_pipe };
    errdefer fd_out.fd.* = .Closed;
    const fd_in = try scheduler.runningProcess.getAvailableFd();
    fd_in.fd.* = .{ .PipeIn = new_pipe };
    errdefer fd_in.fd.* = .Closed;
    new_pipe.* = Pipe{ .refcount = 2 };
    ks_fds[0] = fd_out.i;
    ks_fds[1] = fd_in.i;
    return 0;
}

fn close(fd: usize) isize {
    const descriptor = &scheduler.runningProcess.fd[fd];
    descriptor.close();
    return 0;
}
