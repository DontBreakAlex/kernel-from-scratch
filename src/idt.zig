const vga = @import("vga.zig");
const utils = @import("utils.zig");
const paging = @import("memory/paging.zig");

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

const NUMBER_OF_ENTRIES: u16 = 256;
// The total size of all the IDT entries (-1 for the same reason as the GDT).
const TABLE_SIZE: u16 = @sizeOf(IdtEntry) * NUMBER_OF_ENTRIES - 1;
const ISR_GATE_TYPE = 0xE; // 80386 32-bit interrupt gate
const KERN_CODE = 0x08;

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

fn buildEntry(base: usize, selector: u16, gate_type: u4, privilege: u2) IdtEntry {
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

pub fn setIdtEntry(index: u8, handler: usize) void {
    idt_entries[index] = buildEntry(handler, KERN_CODE, ISR_GATE_TYPE, 0x0);
}

const InterruptHandler = fn (*Regs) void;

pub fn setInterruptHandler(index: u8, comptime handler: InterruptHandler, comptime save_fpu: bool) void {
    const isr = @ptrToInt(buildIsr(handler, save_fpu));
    idt_entries[index] = buildEntry(isr, KERN_CODE, ISR_GATE_TYPE, 0x0);
}

fn buildIsr(comptime handler: InterruptHandler, comptime save_fpu: bool) fn () callconv(.Naked) void {
    return struct {
        fn func() callconv(.Naked) void {
            asm volatile (
            // \\xchg %%bx, %%bx
                \\cli
                \\pusha
            );
            if (save_fpu) {
                asm volatile (
                    \\mov %%esp, %%ebp
                    \\sub $512, %%esp
                    \\andl $0xFFFFFFF0, %%esp
                    \\fxsave (%%esp)
                );
            }
            // if (need_cr3) {
            //     asm volatile (
            //         \\mov %%cr3, %%eax
            //         \\push %%eax
            //         \\mov %[pd], %%cr3
            //         :
            //         : [pd] "r" (paging.kernelPageDirectory.cr3),
            //         : "eax", "memory"
            //     );
            // }

            @setRuntimeSafety(false);
            handler(@intToPtr(*Regs, asm volatile (""
                : [ret] "={ebp}" (-> usize),
            )));

            // if (need_cr3) {
            //     asm volatile (
            //         \\pop %%eax
            //         \\mov %%eax, %%cr3
            //         ::: "eax", "memory");
            // }
            if (save_fpu) {
                asm volatile (
                    \\fxrstor (%%esp)
                    \\mov %%ebp, %%esp
                );
            }
            asm volatile (
                \\popa
                \\sti
                \\iret
            );
        }
    }.func;
}

extern fn boch_break() void;
extern fn enable_int() void;

extern var isr_stub_table: [32]u32;
pub fn init() void {
    var i: u8 = 0;
    while (i < 32) : (i += 1) {
        setIdtEntry(i, isr_stub_table[i]);
    }

    idt_ptr.base = @ptrToInt(&idt_entries);
    idt_ptr.limit = TABLE_SIZE;
    utils.lidt(&idt_ptr);

    vga.putStr("IDT Initialized\n");
}

const InterruptFrame = packed struct {
    index: usize,
    code: usize,
    eip: usize,
    cs: usize,
    eflags: usize,
};

export fn exception(frame: *InterruptFrame) callconv(.C) void {
    vga.format("Exception: {s} with code {d} at 0x{x:0>8}\n", .{
        EXCEPTIONS[frame.index],
        frame.code,
        frame.eip,
    });
    if (frame.index == 14) {
        vga.format("Fauld addr: 0x{x:0>8}\n", .{utils.get_register(.cr2)});
        utils.halt();
    }
}

const EXCEPTIONS: [32][]const u8 = .{
    "Divide by zero",
    "Debug",
    "Non-maskable interrupt",
    "Breakpoint",
    "Overflow",
    "Bound range exceeded",
    "Invalid opcode",
    "Device not available",
    "Double fault",
    "Coprocessor segment overrun",
    "Invalid TSS",
    "Segment not present",
    "Stack segmentation fault",
    "General protection fault",
    "Page fault",
    "Reserved (0x0F)",
    "x87 floating-point exception",
    "Alignemnt check",
    "Machine check",
    "SIMD floating-point exception",
    "Virtualization exception",
    "Reserved (0x15)",
    "Reserved (0x16)",
    "Reserved (0x17)",
    "Reserved (0x18)",
    "Reserved (0x19)",
    "Reserved (0x1a)",
    "Reserved (0x1b)",
    "Reserved (0x1c)",
    "Reserved (0x1d)",
    "Security exception",
    "Reserved (0x1f)",
};

pub const Regs = struct {
    edi: usize,
    esi: usize,
    ebp: usize,
    esp: usize,
    ebx: usize,
    edx: usize,
    ecx: usize,
    eax: usize,
};
