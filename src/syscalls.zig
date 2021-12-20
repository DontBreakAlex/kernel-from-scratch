const std = @import("std");
const paging = @import("memory/paging.zig");

var stack: [1024]u8 align(16) = undefined;

pub fn kernCall(comptime func: anytype, args: anytype) usize {
    const old_cr3 = asm volatile ("mov %%cr3, %%eax"
        : [ret] "={eax}" (-> usize),
    );
    if (old_cr3 == @ptrToInt(paging.kernelPageDirectory.cr3)) {
        return @call(.{}, func, args);
    } else {
        const val = @call(.{ .stack = &stack }, callWithCr3, .{ old_cr3, func, args });

        return val;
    }
}

inline fn callWithCr3(old_cr3: usize, func: anytype, args: anytype) usize {
    asm volatile (
        \\mov %[new_cr3], %%cr3
        :
        : [new_cr3] "r" (paging.kernelPageDirectory.cr3),
        : "memory"
    );
    const val = @call(.{}, func, args);
    asm volatile (
        \\mov %[old_cr3], %%cr3
        :
        : [old_cr3] "r" (old_cr3),
        : "memory"
    );
    return val;
}

pub fn kernelCallNoRet(comptime func: anytype, args: anytype) void {
    @call(.{}, func, args);
}
