const std = @import("std");
const paging = @import("memory/paging.zig");
const scheduler = @import("scheduler.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");

pub fn init() void {
    idt.setInterruptHandler(0x80, syscall_handler, true);
}

pub fn syscall_handler(regs: *idt.Regs) void {
    asm volatile (
        \\mov %%cr3, %%ecx
        \\mov %%esp, %%edx
        \\mov $0x1000000, %%esp
        \\mov %[new_cr3], %%cr3
        \\push %%ecx
        \\push %%edx
        \\push %[reg_ptr]
        \\call syscallHandlerInKS
        \\add $4, %%esp
        \\xchg %%bx, %%bx
        \\pop %%edx
        \\pop %%ecx
        \\mov %%ecx, %%cr3
        \\mov %%edx, %%esp
        :
        : [reg_ptr] "r" (regs),
          [new_cr3] "r" (paging.kernelPageDirectory.cr3),
        : "ecx", "edx", "memory"
    );
}

export fn syscallHandlerInKS(regs_ptr: usize) callconv(.C) void {
    vga.format("0x{x:0>8}\n", .{regs_ptr});
}

// pub fn kernCall(comptime func: anytype, args: anytype) usize {
//     const old_cr3 = asm volatile("mov %%cr3, %%eax": [ret] "={eax}" (-> usize));
//     if (old_cr3 == @ptrToInt(paging.kernelPageDirectory.cr3)) {
//         return @call(.{}, func, args);
//     } else {
//         var result: usize = undefined;
//         const old_esp = asm volatile ("" : [ret] "={esp}" (-> usize));
//         asm volatile (
//             \\mov 0x1000000, %%esp
//             \\mov %[new_cr3], %%cr3
//             :
//             : [new_cr3] "r" (paging.kernelPageDirectory.cr3)
//             : "memory"
//         );
//         kernCallHelper(func, @ptrToInt(&args), @TypeOf(args), &result);
//         asm volatile (
//             \\mov %[old_esp], %%esp
//             \\mov %[old_cr3], %%cr3
//             :
//             : [old_cr3] "r" (old_cr3),
//               [old_esp] "r" (old_esp)
//             : "memory"
//         );
//         return result;
//     }
// }

// fn kernCallHelper(comptime func: anytype, arg_ptr: usize, comptime arg_type: type, result: *usize) void {
//     const result_in_us: *usize = if (scheduler.runningProcess.cr3.virtToPhy(@ptrToInt(result))) |res| @intToPtr(*usize, res) else @panic("Virt to phy failed in kernCall");
//     const args_in_us = if (scheduler.runningProcess.cr3.virtToPhy(arg_ptr)) |arg| @intToPtr(*arg_type, arg) else @panic("Virt to phy failed in kernCall");
//     result_in_us.* = @call(.{}, func, args_in_us.*);
// }

// pub fn kernelCallNoRet(comptime func: anytype, args: anytype) void {
//     @call(.{}, func, args);
// }
