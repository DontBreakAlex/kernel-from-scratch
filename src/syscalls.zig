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

export fn syscallHandlerInKS(regs_ptr: *idt.Regs, cr3: *[1024]PageEntry, us_esp: usize) callconv(.C) void {
    const PD = PageDirectory{ .cr3 = cr3 };
    const regs = mem.mapStructure(idt.Regs, regs_ptr, PD) catch |err| {
        vga.format("{}\n", .{err});
        @panic("Syscall failure");
    };
    @setRuntimeSafety(false);
    regs.eax = @intCast(usize, switch (regs.eax) {
        9 => mmap(regs.ebx),
        39 => getpid(),
        57 => fork(regs_ptr, us_esp),
        else => {
            @panic("Unhandled syscall");
        },
    });
    // TODO: Try to reuse maps
    mem.unMapStructure(idt.Regs, regs);
}

fn mmap(count: usize) isize {
    return @intCast(isize, scheduler.runningProcess.allocPages(count) catch 0);
}

fn getpid() isize {
    return scheduler.runningProcess.pid;
}

fn fork(regs_ptr: *idt.Regs, us_esp: usize) isize {
    const new_process = scheduler.runningProcess.clone() catch |err| {
        vga.format("{}\n", .{err});
        return @as(isize, -1);
    };
    new_process.data.esp = us_esp + 20;
    new_process.data.regs = @ptrToInt(regs_ptr);
    new_process.data.restore();
    return new_process.data.pid;
}
