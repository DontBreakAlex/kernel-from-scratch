const std = @import("std");
const paging = @import("memory/paging.zig");
const scheduler = @import("scheduler.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const mem = @import("memory/mem.zig");

const PageDirectory = paging.PageDirectory;
const PageEntry = paging.PageEntry;

pub fn init() void {
    idt.setInterruptHandler(0x80, syscall_handler, true);
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

pub fn syscall_handler(regs: *idt.Regs) void {
    asm volatile (
        \\mov %%cr3, %%ecx
        \\mov %%esp, %%edx
        \\mov %[new_cr3], %%cr3
        \\mov (%[new_stack]), %%esp
        \\push %%edx
        \\push %%ecx
        \\push %[reg_ptr]
        \\call syscallHandlerInKS
        \\add $4, %%esp
        \\pop %%ecx
        \\pop %%edx
        \\mov %%ecx, %%cr3
        \\mov %%edx, %%esp
        :
        : [reg_ptr] "r" (regs),
          [new_cr3] "r" (paging.kernelPageDirectory.cr3),
          [new_stack] "r" (&scheduler.runningProcess.kstack),
        : "ecx", "edx", "memory"
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
    const regs = mem.mapStructure(idt.Regs, regs_ptr, PD) catch |err| {
        vga.format("{}\n", .{err});
        @panic("Syscall failure");
    };
    @setRuntimeSafety(false);
    regs.eax = @bitCast(usize, switch (regs.eax) {
        0 => read(regs.ebx, regs.ecx, regs.edx),
        9 => mmap(regs.ebx),
        11 => munmap(regs.ebx, regs.ecx),
        // Should be sigaction
        13 => signal(regs.ebx, regs.ecx),
        39 => getpid(),
        57 => fork(regs_ptr, us_esp),
        162 => sleep(),
        else => {
            @panic("Unhandled syscall");
        },
    });
    // TODO: Try to reuse maps
    mem.unMapStructure(idt.Regs, regs) catch unreachable;
    if (scheduler.wantsToSwitch) {
        scheduler.wantsToSwitch = false;
        scheduler.schedule(us_esp + 20, @ptrToInt(regs_ptr), @ptrToInt(u_cr3));
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

fn fork(regs_ptr: *idt.Regs, us_esp: usize) isize {
    const new_process = scheduler.runningProcess.clone() catch |err| {
        vga.format("{}\n", .{err});
        return @as(isize, -1);
    };
    // 20 is the space space used by syscall_handler
    // In case of weird bug, check here (expected issue: FPU data corruption)
    new_process.esp = us_esp + 20;
    new_process.regs = @ptrToInt(regs_ptr);
    scheduler.canSwitch = false;
    scheduler.queue.writeItem(new_process) catch @panic("Queue fail");
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
    return @intCast(isize, scheduler.runningProcess.setSigHanlder(@intToEnum(scheduler.Signal, sig), handler));
}

fn read(fd: usize, buff: usize, count: usize) isize {
    var ret: isize = undefined;
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    if (scheduler.runningProcess.fd[fd]) |descriptor| {
        while (descriptor.readableLength() == 0) {
            scheduler.runningProcess.status = .IO;
            scheduler.queueEvent(descriptor, scheduler.runningProcess) catch return -1;
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
