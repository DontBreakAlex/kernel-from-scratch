const std = @import("std");
const paging = @import("memory/paging.zig");
const scheduler = @import("scheduler.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const mem = @import("memory/mem.zig");
const serial = @import("serial.zig");

const PageDirectory = paging.PageDirectory;
const PageEntry = paging.PageEntry;
const PageAllocator = @import("memory/page_allocator.zig").PageAllocator;
const Event = scheduler.Event;
const Process = scheduler.Process;

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
    const regs = mem.mapStructure(idt.Regs, regs_ptr, PD) catch |err| {
        vga.format("{}\n", .{err});
        @panic("Syscall failure");
    };
    scheduler.canSwitch = true;
    @setRuntimeSafety(false);
    regs.eax = @bitCast(usize, switch (regs.eax) {
        1 => exit(regs.ebx),
        2 => fork(regs_ptr, us_esp) catch -1,
        3 => read(regs.ebx, regs.ecx, regs.edx),
        7 => waitpid(),
        9 => mmap(regs.ebx),
        11 => munmap(regs.ebx, regs.ecx),
        20 => getpid(),
        37 => kill(regs.ebx, regs.ecx),
        48 => signal(regs.ebx, regs.ecx),
        102 => getuid(),
        162 => sleep(),
        222 => usage(regs.ebx) catch -1,
        else => {
            @panic("Unhandled syscall");
        },
    });
    // TODO: Try to reuse maps
    mem.unMapStructure(idt.Regs, regs) catch unreachable;
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
        const regs = try mem.mapStructure(idt.Regs, regs_ptr, new_process.pd);
        regs.eax = 0;
        try mem.unMapStructure(idt.Regs, regs);
    }
    try scheduler.queue.writeItem(new_process);
    scheduler.canSwitch = true;
    return new_process.pid;
}

fn sleep() isize {
    if (!scheduler.canSwitch) {
        unreachable;
    }
    scheduler.wantsToSwitch = true;
    return 0;
}

fn signal(sig: usize, handler: usize) isize {
    return @bitCast(isize, scheduler.runningProcess.setSigHanlder(@intToEnum(scheduler.Signal, @truncate(u8, sig)), handler));
}

fn read(fd: usize, buff: usize, count: usize) isize {
    var ret: isize = undefined;
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    if (scheduler.runningProcess.fd[fd]) |descriptor| {
        while (descriptor.readableLength() == 0) {
            scheduler.queueEvent(Event{ .IO = descriptor }, scheduler.runningProcess) catch return -1;
            scheduler.runningProcess.status = .Sleeping;
            scheduler.canSwitch = true;
            asm volatile ("int $0x81");
            scheduler.canSwitch = false;
        }
        var user_buf = mem.mapBuffer(count, buff, scheduler.runningProcess.pd) catch return -1;
        ret = @intCast(isize, descriptor.read(user_buf));
        mem.unMapBuffer(count, @ptrToInt(user_buf.ptr)) catch @panic("Syscall failure");
    } else {
        ret = -1;
    }
    scheduler.canSwitch = true;
    return ret;
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
    var u_struct = try mem.mapStructure(PageAllocator.AllocatorUsage, @intToPtr(*PageAllocator.AllocatorUsage, u_ptr), scheduler.runningProcess.pd);
    u_struct.* = paging.pageAllocator.usage();
    try mem.unMapStructure(PageAllocator.AllocatorUsage, u_struct);
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
