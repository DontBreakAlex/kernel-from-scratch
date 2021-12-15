const IdtPtr = @import("idt.zig").IdtPtr;
const std = @import("std");
const mlb = @import("multiboot.zig");
const vga = @import("vga.zig");

pub inline fn lidt(ptr: *const IdtPtr) void {
    asm volatile ("lidt (%%eax)"
        :
        : [ptr] "{eax}" (ptr),
    );
}

pub inline fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        else => @compileError("Invalid data type, found: " ++ @typeName(Type)),
    };
}

pub inline fn out(port: u16, data: anytype) void {
    switch (@TypeOf(data)) {
        u8 => asm volatile ("outb %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{al}" (data),
        ),
        u16 => asm volatile ("outw %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{ax}" (data),
        ),
        u32 => asm volatile ("outl %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{eax}" (data),
        ),
        else => @compileError("Invalid data type, found: " ++ @typeName(data)),
    }
}

pub inline fn ioWait() void {
    out(0x80, @as(u8, 0));
}

pub inline fn boch_break() void {
    asm volatile ("xchg %%bx, %%bx");
}

pub inline fn disable_int() void {
    asm volatile ("cli");
}

pub inline fn enable_int() void {
    asm volatile ("sti");
}

pub inline fn halt() void {
    asm volatile (
        \\cli
        \\hlt
    );
}

const Register = enum { esp, ebx, cr2 };

pub fn get_register(comptime reg: Register) usize {
    return switch (reg) {
        .esp => asm volatile (""
            : [ret] "={esp}" (-> usize),
        ),
        .ebx => asm volatile (""
            : [ret] "={ebx}" (-> usize),
        ),
        .cr2 => asm volatile ("mov %%cr2, %%eax"
            : [ret] "={eax}" (-> usize),
        ),
    };
}

pub fn printTrace() void {
    const first_trace_addr = @returnAddress();
    var it = std.debug.StackIterator.init(first_trace_addr, null);
    while (it.next()) |return_address| {
        const name: [*:0]const u8 = mlb.getSymbolName(return_address) catch "??????";
        vga.format("{x:0>8} ({s})\n", .{ return_address, name });
    }
}

pub fn divCeil(numerator: usize, denomiator: usize) usize {
    const quot = numerator / denomiator;
    const rem = numerator % denomiator;
    return quot + @boolToInt(rem != 0);
}

pub fn cleanRegs() void {
    asm volatile (
        \\xor %%eax, %%eax
        \\xor %%ebx, %%ebx
        \\xor %%ecx, %%ecx
        \\xor %%edx, %%edx
        \\xor %%edi, %%edi
        \\xorps %%xmm0, %%xmm0
        \\xorps %%xmm1, %%xmm1
        \\xorps %%xmm2, %%xmm2
        \\xorps %%xmm3, %%xmm3
        \\xorps %%xmm4, %%xmm4
        \\xorps %%xmm5, %%xmm5
        \\xorps %%xmm6, %%xmm6
        \\xorps %%xmm7, %%xmm7
    );
}

extern const stack_top: u8;

/// Saves the stack (including its own stack frame) to the provided buffer.
pub fn saveStack(buf: []u8) !void {
    const bottom: usize = get_register(.esp);
    const top: *const u8 = &stack_top;
    const len = (@ptrToInt(top) - bottom);
    if (len > buf.len)
        return error.BufferToSmall;
    const s = @intToPtr([*]u8, bottom)[0..bottom];
    std.mem.copy(u8, buf, s);
}
