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
const cache = @import("io/cache.zig");

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
    serial.format("{}\n", .{ regs.eax });
    @setRuntimeSafety(false);
    userEax.* = switch (regs.eax) {
        1 => @import("syscalls/exit.zig").exit(regs.ebx),
        2 => fork(regs, saved_esp) catch |err| cat: {
            serial.format("Fork error: {}\n", .{err});
            break :cat -1;
        },
        3 => read(regs.ebx, regs.ecx, regs.edx),
        4 => @import("syscalls/write.zig").write(regs.ebx, regs.ecx, regs.edx),
        5 => @import("syscalls/open.zig").open(regs.ebx, regs.ecx, regs.edx, @truncate(u16, regs.esi)),
        6 => close(regs.ebx),
        7 => waitpid(),
        11 => @import("syscalls/execve.zig").execve(regs.ebx, regs.ecx, frame, regs),
        13 => @import("syscalls/time.zig").time(regs.ebx),
        20 => getpid(),
        36 => sync(),
        37 => kill(regs.ebx, regs.ecx),
        42 => @import("syscalls/pipe.zig").pipe(regs.ebx) catch -1,
        45 => @import("syscalls/brk.zig").brk(regs.ebx),
        48 => signal(regs.ebx, regs.ecx),
        54 => @import("syscalls/ioctl.zig").ioctl(regs.ebx, regs.ecx, regs.edx),
        78 => getdents(regs.ebx, regs.ecx, regs.edx),
        79 => getcwd(regs.ebx, regs.ecx),
        80 => chdir(regs.ebx, regs.ecx),
        500 => mmap(regs.ebx),
        501 => munmap(regs.ebx, regs.ecx),
        102 => getuid(),
        146 => @import("syscalls/write.zig").writev(regs.ebx, regs.ecx, regs.edx),
        162 => sleep(),
        177 => sigwait(),
        195 => @import("syscalls/stat.zig").stat64(regs.ebx, regs.ecx),
        222 => usage(regs.ebx) catch -1,
        223 => command(regs.ebx),
        243 => @import("syscalls/thread.zig").set_thread_area(regs.ebx),
        252 => @import("syscalls/exit.zig").exit(regs.ebx),
        258 => @import("syscalls/thread.zig").set_tid_address(regs.ebx),
        else => blk: {
            serial.format("Unhandled syscall: {}\n", .{regs.eax});
            // @panic("Unhandled syscall");
            break :blk -58;
        },
    };
    // serial.format("eax = {}\n", .{ userEax.* });
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

noinline fn getpid() isize {
    return scheduler.runningProcess.pid;
}

noinline fn getuid() isize {
    return scheduler.runningProcess.owner_id;
}

noinline fn fork(regs_ptr: *idt.Regs, us_esp: usize) !isize {
    const new_process = try scheduler.runningProcess.clone();
    errdefer new_process.deinit();
    new_process.state.SavedState.esp = us_esp;
    new_process.state.SavedState.regs = @ptrToInt(regs_ptr);
    scheduler.canSwitch = false;
    {
        const regs = try new_process.pd.vPtrToPhy(idt.Regs, regs_ptr);
        regs.eax = 0;
    }
    try scheduler.queue.writeItem(new_process);
    scheduler.canSwitch = true;
    return new_process.pid;
}

noinline fn sleep() isize {
    if (!scheduler.canSwitch)
        unreachable;
    scheduler.wantsToSwitch = true;
    return 0;
}

noinline fn signal(sig: usize, handler: usize) isize {
    return @bitCast(isize, scheduler.runningProcess.setSigHanlder(@intToEnum(proc.Signal, @truncate(u8, sig)), handler));
}

noinline fn read(fd: usize, buff: usize, count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    if (scheduler.runningProcess.fd[fd]) |file| {
        var user_buf = scheduler.runningProcess.pd.vBufferToPhy(count, buff) catch return -1;
        return @intCast(isize, file.read(user_buf) catch return -1);
    }
    return -1;
}

noinline fn usage(u_ptr: usize) !isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    var u_struct = try scheduler.runningProcess.pd.vPtrToPhy(PageAllocator.AllocatorUsage, @intToPtr(*PageAllocator.AllocatorUsage, u_ptr));
    u_struct.* = paging.pageAllocator.usage();
    return 0;
}

noinline fn waitpid() isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    var child = scheduler.runningProcess.childrens.first;
    var prev: ?*proc.Child = null;
    while (true) {
        scheduler.runningProcess.status = .Sleeping;
        scheduler.canSwitch = true;
        asm volatile ("int $0x81");
        scheduler.canSwitch = false;
        while (child) |c| {
            if (c.data.status == .Zombie) {
                const pid = c.data.pid;
                serial.format("Process {} found dead child with PID {}\n", .{ scheduler.runningProcess.pid, pid });
                if (prev) |p| {
                    _ = p.removeNext();
                } else {
                    _ = scheduler.runningProcess.childrens.popFirst();
                }
                c.data.deinit();
                return @intCast(isize, pid);
            }
            prev = c;
            child = c.next;
        }
    }
    return -1;
}

noinline fn kill(pid: usize, sig: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    const process = scheduler.processes.get(@intCast(u16, pid)) orelse return -1;
    process.queueSignal(@intToEnum(proc.Signal, sig)) catch return -1;
    return 0;
}

noinline fn sigwait() isize {
    if (!scheduler.canSwitch)
        unreachable;
    scheduler.runningProcess.status = .Sleeping;
    scheduler.wantsToSwitch = true;
    return 0;
}

noinline fn close(fd: usize) isize {
    if (scheduler.runningProcess.fd[fd]) |file| {
        file.close();
        return 0;
    }
    return -1;
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

noinline fn getcwd(buff: usize, size: usize) isize {
    var user_buf = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    var cnt = scheduler.runningProcess.cwd.copyPath(user_buf) catch return -1;
    user_buf[cnt] = 0;
    return @intCast(isize, cnt) + 1;
}

noinline fn chdir(buff: usize, size: usize) isize {
    var path = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    scheduler.runningProcess.cwd = scheduler.runningProcess.cwd.resolve(path) catch return -1;
    return 0;
}

noinline fn getdents(fd: usize, buff: usize, size: usize) isize {
    if (fd >= proc.FD_COUNT) return -1;
    var ptr = @intToPtr([*]Dentry, scheduler.runningProcess.pd.virtToPhy(buff) orelse return -1);
    var cnt = size;
    var file = scheduler.runningProcess.fd[fd] orelse return -1;
    _ = file.getDents(ptr, &cnt) catch return -1;
    return @intCast(isize, cnt);
}

noinline fn sync() isize {
    cache.syncAllBuffers();
    fs.root_fs.sync() catch {};
    return 0;
}
