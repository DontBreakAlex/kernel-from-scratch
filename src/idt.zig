const std = @import("std");
const main = @import("kernel_main.zig");

pub const IdtEntry = packed struct {
    base_low: u16,
    selector: u16,
    zero: u8,
    gate_type: u4,
    storage_segment: u1,
    privilege: u2,
    present: u1,
    base_high: u16,
};

pub const IdtPtr = packed struct {
    limit: u16,
    base: u32,
};

const InterruptHandler = fn () callconv(.Naked) void;

// The total size of all the IDT entries (-1 for the same reason as the GDT).
const TABLE_SIZE: u16 = @sizeOf(IdtEntry) * NUMBER_OF_ENTRIES - 1;
const NUMBER_OF_ENTRIES: u16 = 256;
const KERNEL_CODE_OFFSET = 0x8; // TODO: Import this from gdt.s
const ISR_GATE_TYPE = 0xE; // 80386 32-bit interrupt gate

extern var isr_stub_table: [*]InterruptHandler;

var idt_ptr: IdtPtr = IdtPtr{
    .limit = TABLE_SIZE,
    .base = 0,
};

// Init all ISRs to 0
var idt_entries: [NUMBER_OF_ENTRIES]IdtEntry = [_]IdtEntry{IdtEntry{
    .base_low = 0,
    .selector = 0,
    .zero = 0,
    .gate_type = 0,
    .storage_segment = 0,
    .privilege = 0,
    .present = 0, // CPU won't do anything
    .base_high = 0,
}} ** NUMBER_OF_ENTRIES;

fn buildEntry(base: u32, selector: u16, gate_type: u4, privilege: u2) IdtEntry {
    return IdtEntry{
        .base_low = @truncate(u16, base),
        .selector = selector,
        .zero = 0,
        .gate_type = gate_type,
        .storage_segment = 0,
        .privilege = privilege,
        .present = 1,
        .base_high = @truncate(u16, base >> 16),
    };
}

pub fn setIdtEntry(index: u8, handler: InterruptHandler) void {
    idt_entries[index] = buildEntry(@ptrToInt(handler), KERNEL_CODE_OFFSET, ISR_GATE_TYPE, 0x0);
}

pub fn setup() void {
    comptime var i = 0;
    inline while (i < 32) : (i += 1) {
        setIdtEntry(i, isr_stub_table[i]);
    }

    idt_ptr.base = @ptrToInt(&idt_entries);
    lidt(&idt_ptr);
}

fn lidt(ptr: *const IdtPtr) void {
    asm volatile ("lidt (%%eax)"
        :
        : [ptr] "{eax}" (ptr)
    );
}

export fn exception_code(code: u32) callconv(.C) void {
    var buffer: [32]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "Got exception with code {d}", .{code}) catch "Formating failed";
    main.vgaPutStr(message);
}

export fn exception_nocode() callconv(.C) void {
    main.vgaPutStr("Got exception without code");
}
