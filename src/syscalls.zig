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
const Dentry = dirent.Dentry;

pub fn init() void {
    idt.setIdtEntry(0x80, @ptrToInt(syscall_handler));
    idt.setIdtEntry(0x81, @ptrToInt(preempt));
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
        \\mov (%[new_stack]), %%esp
        \\push %%edx
        \\push %%ecx
        \\push %%ebp
        \\call syscallHandlerInKS
        \\add $4, %%esp
        \\pop %%ecx
        \\pop %%edx
        \\mov %%ecx, %%cr3
        \\mov %%edx, %%esp
        \\fxrstor (%%esp)
        \\mov %%ebp, %%esp
        \\popa
        \\iret
        :
        : [new_cr3] "r" (paging.kernelPageDirectory.cr3),
          [new_stack] "r" (&scheduler.runningProcess.kstack),
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

export fn syscallHandlerInKS(regs_ptr: *Regs, u_cr3: *[1024]PageEntry, us_esp: usize) callconv(.C) void {
    const PD = PageDirectory{ .cr3 = u_cr3 };
    scheduler.canSwitch = false;
    const regs = PD.vPtrToPhy(Regs, regs_ptr) catch |err| {
        vga.format("{}\n", .{err});
        @panic("Syscall failure");
    };
    const userEax: *volatile isize = @ptrCast(*volatile isize, &regs.eax);
    scheduler.canSwitch = true;
    @setRuntimeSafety(false);
    userEax.* = switch (regs.eax) {
        1 => exit(regs.ebx),
        2 => fork(regs_ptr, us_esp) catch |err| cat: {
            serial.format("Fork error: {}\n", .{err});
            break :cat -1;
        },
        3 => read(regs.ebx, regs.ecx, regs.edx),
        4 => write(regs.ebx, regs.ecx, regs.edx),
        5 => @import("syscalls/open.zig").open(regs.ebx, regs.ecx, regs.edx, @truncate(u16, regs.esi)),
        6 => close(regs.ebx),
        7 => waitpid(),
        9 => mmap(regs.ebx),
        11 => munmap(regs.ebx, regs.ecx),
        20 => getpid(),
        36 => sync(),
        37 => kill(regs.ebx, regs.ecx),
        42 => @import("syscalls/pipe.zig").pipe(regs.ebx) catch -1,
        48 => signal(regs.ebx, regs.ecx),
        78 => getdents(regs.ebx, regs.ecx, regs.edx),
        79 => getcwd(regs.ebx, regs.ecx),
        80 => chdir(regs.ebx, regs.ecx),
        102 => getuid(),
        162 => sleep(),
        177 => sigwait(),
        222 => usage(regs.ebx) catch -1,
        223 => command(regs.ebx),
        else => {
            @panic("Unhandled syscall");
        },
    };
    // serial.format("eax = {}\n", .{ userEax.* });
    if (scheduler.wantsToSwitch) {
        scheduler.wantsToSwitch = false;
        scheduler.schedule(us_esp, @ptrToInt(regs_ptr), @ptrToInt(u_cr3));
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

noinline fn write(fd: usize, buff: usize, count: usize) isize {
    scheduler.canSwitch = false;
    defer scheduler.canSwitch = true;
    if (scheduler.runningProcess.fd[fd]) |file| {
        var user_buf = scheduler.runningProcess.pd.vBufferToPhy(count, buff) catch return -1;
        return @intCast(isize, file.write(user_buf) catch return -1);
    }
    return -1;
}

noinline fn exit(code: usize) isize {
    scheduler.canSwitch = false;
    scheduler.runningProcess.status = .Zombie;
    scheduler.runningProcess.state = .{ .ExitCode = code };
    if (scheduler.runningProcess.parent) |parent| {
        if (parent.status == .Sleeping) {
            parent.status = .Paused;
            scheduler.queue.writeItem(parent) catch @panic("Alloc failure in exit");
        }
    } else @panic("Init process exited");
    scheduler.canSwitch = true;
    scheduler.schedule(undefined, undefined, undefined);
    return 0;
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
    const result = scheduler.runningProcess.cwd.resolve(path, &scheduler.runningProcess.cwd) catch return -1;
    return if (result == .Found) 0 else -1;
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
    cache.syncAll();
    fs.root_fs.sync() catch {};
    return 0;
}
