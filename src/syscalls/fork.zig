const serial = @import("../serial.zig");
const scheduler = @import("../scheduler.zig");
const idt = @import("../idt.zig");

const Regs = idt.Regs;

pub noinline fn fork(regs_ptr: *idt.Regs, us_esp: usize) isize {
    if (comptime @import("../constants.zig").DEBUG)
        serial.format("fork called", .{});
    return do_fork(regs_ptr, us_esp) catch -1;
}

fn do_fork(regs_ptr: *Regs, us_esp: usize) !isize {
    const new_process = try scheduler.runningProcess.clone();
    errdefer new_process.deinit();
    new_process.state.SavedState.esp = us_esp;
    new_process.state.SavedState.regs = @ptrToInt(regs_ptr);
    scheduler.canSwitch = false;
    {
        const regs = try new_process.pd.vPtrToPhy(Regs, regs_ptr);
        regs.eax = 0;
    }
    try scheduler.queue.writeItem(new_process);
    scheduler.canSwitch = true;
    return new_process.pid;
}
