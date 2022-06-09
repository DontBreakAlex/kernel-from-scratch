const std = @import("std");
const fs = @import("io/fs.zig");
const vga = @import("vga.zig");
const mem = @import("memory/mem.zig");
const vmem = @import("memory/vmem.zig");
const proc = @import("process.zig");
const utils = @import("utils.zig");
const serial = @import("serial.zig");
const paging = @import("memory/paging.zig");
const dirent = @import("io/dirent.zig");
const keyboard = @import("keyboard.zig");
const cache = @import("io/cache.zig");
const fcntl = @import("io/fcntl.zig");
const log = @import("log.zig");

const Process = proc.Process;
const PageDirectory = paging.PageDirectory;
const allocator = mem.allocator;
const US_STACK_BASE = proc.US_STACK_BASE;
const KERNEL_STACK_SIZE = proc.KERNEL_STACK_SIZE;
const InodeRef = dirent.InodeRef;

pub var wantsToSwitch: bool = false;
pub var canSwitch: bool = true;

const ProcessMap = std.AutoHashMap(u16, *Process);
const ProcessQueue = std.fifo.LinearFifo(*Process, .Dynamic);
const EventList = std.ArrayListUnmanaged(*Process);
const Events = std.AutoHashMap(Event, EventList);
const Fn = fn () void;
pub const Event = union(enum) {
    IO_READ: InodeRef,
    IO_WRITE: InodeRef,
    CHILD,
};

pub var queue: ProcessQueue = ProcessQueue.init(allocator);
pub var events: Events = Events.init(allocator);
pub var processes: ProcessMap = ProcessMap.init(allocator);
pub var runningProcess: *Process = undefined;

const Children = proc.Children;
const SignalQueue = proc.SignalQueue;
const ProcessState = proc.ProcessState;
pub fn startProcess(func: Fn) !void {
    const process: *Process = try allocator.create(Process);
    process.pid = proc.getNewPid();
    process.status = .Running;
    process.childrens = Children{};
    process.signals = SignalQueue.init(allocator);
    process.handlers = .{0} ** 1;
    process.pd = try PageDirectory.init();
    process.state = .{ .SavedState = ProcessState{
        .cr3 = @ptrToInt(process.pd.cr3),
        .esp = US_STACK_BASE,
        .regs = 0,
    } };
    process.cwd = &fs.root_dirent;
    process.owner_id = 0;
    process.vmem = vmem.VMemManager{};
    process.vmem.init();
    process.fd = .{null} ** proc.FD_COUNT;
    var dentry = try dirent.DirEnt.create(.{ .pipe = &keyboard.inode }, null, &.{}, dirent.Type.CharDev);
    process.fd[0] = try fs.File.create(dentry, fcntl.O_RDONLY);
    dentry.release();
    errdefer process.fd[0].?.close();
    process.parent = null;

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try process.pd.mapOneToOne(paging.PAGE_SIZE * i);
    }
    serial.format("Shell has PD at 0x{x:0>8}\n", .{@ptrToInt(process.pd.cr3)});
    process.kstack = try mem.allocKstack(2);
    serial.format("Kernel stack bottom: 0x{x:0>8}\n", .{process.kstack});
    var esp = try paging.pageAllocator.alloc();
    try process.pd.mapVirtToPhy(process.state.SavedState.esp - paging.PAGE_SIZE, esp, paging.WRITE);
    process.state.SavedState.esp -= 16;
    esp += 4088;
    @intToPtr(*usize, esp).* = 0x202; // eflags
    esp -= 4;
    @intToPtr(*usize, esp).* = 0x8; // cs
    esp -= 4;
    @intToPtr(*usize, esp).* = @ptrToInt(func); // eip
    // utils.boch_break();
    try processes.put(process.pid, process);
    process.start();
}

pub export fn schedule(esp: usize, regs: usize, cr3: usize) callconv(.C) void {
    canSwitch = false;
    switch (runningProcess.status) {
        .Sleeping => {
            if (queue.count == 0) {
                idleInit();
                while (queue.count == 0)
                    idle();
            }
            runningProcess.save(esp, regs, cr3);
            runningProcess = queue.readItem() orelse @panic("Scheduler failed");
        },
        .Running => {
            runningProcess.status = .Paused;
            runningProcess.save(esp, regs, cr3);
            if (queue.count != 0) {
                queue.writeItem(runningProcess) catch @panic("Scheduler failed");
                runningProcess = queue.readItem() orelse @panic("Scheduler failed");
            }
        },
        .Zombie => {
            if (queue.count == 0) {
                if (events.count() == 0)
                    @panic("Attempt to kill last process !");
                idleInit();
                while (queue.count == 0)
                    idle();
            }
            runningProcess = queue.readItem() orelse @panic("Scheduler failed");
        },
        else => @panic("Scheduler interupted non-running process (?!)"),
    }
    runningProcess.status = .Running;
    canSwitch = true;
    runningProcess.restore();
}

const Buffer = cache.Buffer;
const idleData = struct {
    var begin_at: ?*Buffer = null;
};
fn idleInit() void {
    cache.syncAllInodes() catch log.format("/!\\ Failed to sync inodes !", .{});
    idleData.begin_at = cache.syncBuffersInit();
}

fn idle() void {
    asm volatile ("sti");
    if (idleData.begin_at) |at|
        if (cache.syncOneBuffer(at)) |ret| {
            idleData.begin_at = ret;
            return;
        };
    asm volatile ("hlt");
    return;
}

pub fn queueEvent(key: Event, val: *Process) !void {
    var res = try events.getOrPut(key);
    var array: *EventList = res.value_ptr;
    if (!res.found_existing)
        array.* = EventList{};
    try array.append(allocator, val);
}

pub fn writeWithEvent(inode: InodeRef, src: []const u8, offset: usize) !usize {
    if (events.getPtr(Event{ .IO_WRITE = inode })) |array| {
        try queue.ensureUnusedCapacity(array.items.len);
        const ret = try inode.rawWrite(src, offset);
        queue.writeAssumeCapacity(array.items);
        array.clearRetainingCapacity();
        return ret;
    } else {
        return inode.rawWrite(src, offset);
    }
}

pub fn readWithEvent(inode: InodeRef, dst: []u8, offset: usize) !usize {
    var ret: usize = undefined;
    if (events.getPtr(Event{ .IO_READ = inode })) |array| {
        try queue.ensureUnusedCapacity(array.items.len);
        ret = try inode.rawRead(dst, offset);
        queue.writeAssumeCapacity(array.items);
        array.clearRetainingCapacity();
    } else {
        ret = try inode.rawRead(dst, offset);
    }
    return ret;
}

pub fn waitForEvent(event: Event) !void {
    try queueEvent(event, runningProcess);
    runningProcess.status = .Sleeping;
    canSwitch = true;
    asm volatile ("int $0x81");
    canSwitch = false;
}
