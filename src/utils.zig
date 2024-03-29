const IdtPtr = @import("idt.zig").IdtPtr;
const paging = @import("memory/paging.zig");
const std = @import("std");
const mlb = @import("multiboot.zig");
const vga = @import("vga.zig");
const log = @import("log.zig");

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

const Register = enum { esp, ebx, ebp, cr2, cr3 };

pub inline fn get_register(comptime reg: Register) usize {
    return switch (reg) {
        .esp => asm volatile (""
            : [ret] "={esp}" (-> usize),
        ),
        .ebx => asm volatile (""
            : [ret] "={ebx}" (-> usize),
        ),
        .ebp => asm volatile (""
            : [ret] "={ebp}" (-> usize),
        ),
        .cr2 => asm volatile ("mov %%cr2, %%eax"
            : [ret] "={eax}" (-> usize),
        ),
        .cr3 => asm volatile ("mov %%cr3, %%eax"
            : [ret] "={eax}" (-> usize),
        ),
    };
}

pub fn printTrace() void {
    const first_trace_addr = @returnAddress();
    var it = std.debug.StackIterator.init(first_trace_addr, null);
    while (it.next()) |return_address| {
        const name: [*:0]const u8 = mlb.getSymbolName(return_address) catch "??????";
        log.format("{x:0>8} ({s})\n", .{ return_address, name });
    }
}

pub fn divCeil(numerator: usize, denomiator: usize) usize {
    const quot = numerator / denomiator;
    const rem = numerator % denomiator;
    return quot + @boolToInt(rem != 0);
}

pub const Buffer = std.fifo.LinearFifo(u8, std.fifo.LinearFifoBufferType{ .Static = 32 });

pub inline fn getNthBit(buff: []const u8, n: usize) u1 {
    @setRuntimeSafety(false);
    const index = n / 8;
    const offset = @intCast(u3, n % 8);
    return @truncate(u1, buff[index] >> offset);
}

pub inline fn setNthBit(buff: []u8, n: usize) void {
    @setRuntimeSafety(false);
    const index = n / 8;
    const offset = @intCast(u3, n % 8);
    buff[index] &= 128 >> offset;
}

const PageDirectory = paging.PageDirectory;

pub fn push(esp: *usize, x: anytype, pd: ?PageDirectory) void {
    esp.* = esp.* - @sizeOf(@TypeOf(x));
    if (pd) |p| {
        (p.vPtrToPhy(@TypeOf(x), @intToPtr(*@TypeOf(x), esp.*)) catch unreachable).* = x;
    } else {
        @intToPtr(*@TypeOf(x), esp.*).* = x;
    }
}
