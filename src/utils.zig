const IdtPtr = @import("idt.zig").IdtPtr;

pub inline fn lidt(ptr: *const IdtPtr) void {
    asm volatile ("lidt (%%eax)"
        :
        : [ptr] "{eax}" (ptr)
    );
}

pub inline fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> Type)
            : [port] "N{dx}" (port)
        ),
        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> Type)
            : [port] "N{dx}" (port)
        ),
        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type)
            : [port] "N{dx}" (port)
        ),
        else => @compileError("Invalid data type, found: " ++ @typeName(Type)),
    };
}

pub inline fn out(port: u16, data: anytype) void {
    switch (@TypeOf(data)) {
        u8 => asm volatile ("outb %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{al}" (data)
        ),
        u16 => asm volatile ("outw %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{ax}" (data)
        ),
        u32 => asm volatile ("outl %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{eax}" (data)
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
