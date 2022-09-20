const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const gdt = @import("../gdt.zig");

const UserDescriptor = packed struct {
    entry_number: u32,
    base_addr: u32,
    limit: u32,
    seg_32bit: u1,
    contents: u2,
    read_exec_only: u1,
    limit_in_pages: u1,
    seg_not_present: u1,
    useable: u1,
};

pub noinline fn set_thread_area(descriptor: usize) isize {
    const phy_descriptor = scheduler.runningProcess.pd.virtToPhy(descriptor) orelse return -1;
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("set_thread_area called with desc=0x{x}", .{phy_descriptor});
    do_set_thread_area(@intToPtr(*UserDescriptor, phy_descriptor));
    return 0;
}

fn do_set_thread_area(descriptor: *UserDescriptor) void {
    if (descriptor.seg_not_present == 1)
        @panic("Attempt to free TLS");
    if (descriptor.entry_number == gdt.TLS_SEG / 8 or descriptor.entry_number == ~@as(u32, 0)) {
        var gdt_segment = gdt.getGDTEntry(gdt.TLS_SEG);
        gdt_segment.limit_low = @truncate(u16, descriptor.limit);
        gdt_segment.base_low = @truncate(u24, descriptor.base_addr);
        gdt_segment.accessed = 0;
        gdt_segment.read_write = ~descriptor.read_exec_only;
        gdt_segment.conforming_expand_down = 1;
        gdt_segment.code = 0; // Maybe use contents ?
        gdt_segment.code_data_segment = 1;
        gdt_segment.DPL = 3;
        gdt_segment.present = 1;
        gdt_segment.limit_high = @truncate(u4, (descriptor.limit >> 16));
        gdt_segment.long_mode = ~descriptor.seg_32bit;
        gdt_segment.available = 1;
        gdt_segment.big = 1;
        gdt_segment.gran = descriptor.limit_in_pages;
        gdt_segment.base_high = @truncate(u8, (descriptor.base_addr >> 24));

        descriptor.entry_number = gdt.TLS_SEG / 8;
    } else {
        @panic("Unhandled TLS");
    }
}

pub noinline fn set_tid_address(addr: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("set_tid_address called {}\n", .{addr});
    return 0;
}
