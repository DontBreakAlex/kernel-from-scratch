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

export fn syscallHandlerInKS(regs_ptr: *idt.Regs, cr3: *[1024]PageEntry) callconv(.C) void {
    const PD = PageDirectory{ .cr3 = cr3 };
    const regs = mem.mapStructure(idt.Regs, regs_ptr, PD) catch @panic("Syscall failure");
    regs.eax = switch (regs.eax) {
        9 => mmap(regs.ebx),
        else => {
            @panic("Unhandled syscall");
        },
    };
    // TODO: Try to reuse maps
    mem.unMapStructure(idt.Regs, regs);
}

fn mmap(count: usize) usize {
    return scheduler.runningProcess.allocPages(count) catch 0;
}
