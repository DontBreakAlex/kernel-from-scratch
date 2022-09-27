const std = @import("std");
const paging = @import("memory/paging.zig");
const scheduler = @import("scheduler.zig");
const idt = @import("idt.zig");
const utils = @import("utils.zig");
const vga = @import("vga.zig");
const mem = @import("memory/mem.zig");
const serial = @import("serial.zig");
const proc = @import("process.zig");
const pipefs = @import("io/pipefs.zig");
const fs = @import("io/fs.zig");
const pipe_ = @import("pipe.zig");
const dirent = @import("io/dirent.zig");

const DEBUG = @import("constants.zig").DEBUG;

const PageDirectory = paging.PageDirectory;
const PageEntry = paging.PageEntry;
const PageAllocator = @import("memory/page_allocator.zig").PageAllocator;
const Event = scheduler.Event;
const Process = scheduler.Process;
const Regs = idt.Regs;
const IretFrame = idt.IretFrame;
const Dentry = dirent.Dentry;

pub fn init() void {
    idt.setIdtEntry(0x80, @ptrToInt(syscall_handler), 3);
    idt.setIdtEntry(0x81, @ptrToInt(preempt), 0);
}

// TODO: Check cr3 and stack
fn preempt() callconv(.Naked) void {
    asm volatile (
        \\pusha
        \\mov %%esp, %%ebp
        \\sub $512, %%esp
        \\andl $0xFFFFFFF0, %%esp
        \\fxsave (%%esp)
        \\mov %%esp, %%ecx
        \\mov %%cr3, %%ebx
        \\push %%ebx
        \\push %%ebp
        \\push %%ecx
        \\call schedule
    );
    @panic("Schedule returned in preempt");
}

pub fn syscall_handler() callconv(.Naked) void {
    asm volatile (
        \\pusha
        \\mov %%esp, %%ebp
        \\sub $512, %%esp
        \\andl $0xFFFFFFF0, %%esp
        \\fxsave (%%esp)
        ::: "ebp");
    asm volatile (
        \\mov %%cr3, %%ecx
        \\mov %%esp, %%edx
        \\mov %[new_cr3], %%cr3
        \\push %%edx
        \\push %%ecx
        \\push %%ebp
        \\call syscallHandlerInKS
        \\add $4, %%esp
        \\pop %%ecx
        \\pop %%edx
        \\mov %%ecx, %%cr3
        \\mov %%edx, %%esp // Probably not needed
        \\fxrstor (%%esp)
        \\mov %%ebp, %%esp
        \\popa
        \\iret
        :
        : [new_cr3] "r" (paging.kernelPageDirectory.cr3),
        : "ebp", "ecx", "edx"
    );
}

// eax: Syscall number
// ebx: arg1
// ecx: arg2
// edx: arg3
// esi: arg4
// edi: arg5
// ebp: arg6

export fn syscallHandlerInKS(regs: *Regs, u_cr3: *[1024]PageEntry, saved_esp: usize) callconv(.C) void {
    scheduler.canSwitch = false;
    const userEax: *volatile isize = @ptrCast(*volatile isize, &regs.eax);
    scheduler.canSwitch = true;
    var frame = @intToPtr(*IretFrame, @ptrToInt(regs) + 32);
    // serial.format("{}\n", .{ regs.eax });
    @setRuntimeSafety(false);
    userEax.* = switch (regs.eax) {
        1 => @import("syscalls/exit.zig").exit(regs.ebx),
        2 => @import("syscalls/fork.zig").fork(regs, saved_esp),
        3 => @import("syscalls/read.zig").read(regs.ebx, regs.ecx, regs.edx),
        4 => @import("syscalls/write.zig").write(regs.ebx, regs.ecx, regs.edx),
        5 => @import("syscalls/open.zig").open(regs.ebx, regs.ecx, @truncate(u16, regs.edx)),
        6 => @import("syscalls/close.zig").close(regs.ebx),
        7 => @import("syscalls/wait.zig").waitpid(regs.ebx, regs.ecx, regs.edx),
        11 => @import("syscalls/execve.zig").execve(regs.ebx, regs.ecx, frame, regs),
        13 => @import("syscalls/time.zig").time(regs.ebx),
        20 => @import("syscalls/get.zig").getpid(),
        24 => @import("syscalls/get.zig").getuid(),
        36 => @import("syscalls/sync.zig").sync(),
        37 => @import("syscalls/kill.zig").kill(regs.ebx, regs.ecx),
        42 => @import("syscalls/pipe.zig").pipe(regs.ebx),
        45 => @import("syscalls/brk.zig").brk(regs.ebx),
        47 => @import("syscalls/get.zig").getgid(),
        48 => @import("syscalls/signal.zig").signal(regs.ebx, regs.ecx),
        49 => @import("syscalls/get.zig").geteuid(),
        50 => @import("syscalls/get.zig").getegid(),
        54 => @import("syscalls/ioctl.zig").ioctl(regs.ebx, regs.ecx, regs.edx),
        55 => @import("syscalls/fcntl.zig").fcntl(regs.ebx, regs.ecx, regs.edx),
        64 => @import("syscalls/get.zig").getppid(),
        78 => @import("syscalls/getdents.zig").getdents(regs.ebx, regs.ecx, regs.edx),
        80 => @import("syscalls/chdir.zig").chdir(regs.ebx, regs.ecx),
        500 => mmap(regs.ebx),
        501 => munmap(regs.ebx, regs.ecx),
        102 => @import("syscalls/get.zig").getuid(),
        108 => @import("syscalls/stat.zig").fstat(regs.ebx, regs.ecx),
        146 => @import("syscalls/write.zig").writev(regs.ebx, regs.ecx, regs.edx),
        162 => @import("syscalls/sleep.zig").nanosleep(regs.ebx, regs.ecx),
        168 => @import("syscalls/poll.zig").poll(regs.ebx, regs.ecx, regs.edx),
        174 => @import("syscalls/sigaction.zig").sigaction(regs.ebx, regs.ecx, regs.edx),
        177 => @import("syscalls/wait.zig").sigwait(),
        183 => @import("syscalls/get.zig").getcwd(regs.ebx, regs.ecx),
        195 => @import("syscalls/stat.zig").stat64(regs.ebx, regs.ecx),
        199 => @import("syscalls/get.zig").getuid(),
        200 => @import("syscalls/get.zig").getgid(),
        201 => @import("syscalls/get.zig").geteuid(),
        202 => @import("syscalls/get.zig").getegid(),
        221 => @import("syscalls/fcntl.zig").fcntl64(regs.ebx, regs.ecx, regs.edx),
        222 => usage(regs.ebx) catch -1,
        223 => command(regs.ebx),
        243 => @import("syscalls/thread.zig").set_thread_area(regs.ebx),
        252 => @import("syscalls/exit.zig").exit(regs.ebx),
        258 => @import("syscalls/thread.zig").set_tid_address(regs.ebx),
        else => blk: {
            serial.format("Unhandled syscall: {}\n", .{regs.eax});
            // @panic("Unhandled syscall");
            break :blk -38;
        },
    };
    if (comptime DEBUG)
        serial.format(", returned {}\n", .{userEax.*});
    if (scheduler.wantsToSwitch) {
        scheduler.wantsToSwitch = false;
        scheduler.schedule(saved_esp, @ptrToInt(regs), @ptrToInt(u_cr3));
    }
}

noinline fn mmap(count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    return @intCast(isize, scheduler.runningProcess.allocPages(count) catch std.math.maxInt(usize));
}

noinline fn munmap(addr: usize, count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    scheduler.runningProcess.deallocPages(addr, count);
    return 0;
}

noinline fn usage(u_ptr: usize) !isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    var u_struct = try scheduler.runningProcess.pd.vPtrToPhy(PageAllocator.AllocatorUsage, @intToPtr(*PageAllocator.AllocatorUsage, u_ptr));
    u_struct.* = paging.pageAllocator.usage();
    return 0;
}

noinline fn command(cmd: usize) isize {
    switch (cmd) {
        0 => {
            serial.format("Running processes: \n", .{});
            var it = scheduler.processes.valueIterator();
            while (it.next()) |process| {
                serial.format("{:0>3}: {}\n", .{ process.*.pid, process.*.status });
            }
            serial.format("Process count: {}\n", .{scheduler.processes.count()});
        },
        else => {},
    }
    return 0;
}
