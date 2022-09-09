const std = @import("std");
const scheduler = @import("../scheduler.zig");
const elf = @import("../elf.zig");
const tty = @import("../tty.zig");
const mem = @import("../memory/mem.zig");
const serial = @import("../serial.zig");
const paging = @import("../memory/paging.zig");
const proc = @import("../process.zig");
const idt = @import("../idt.zig");
const utils = @import("../utils.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const ElfHeader = elf.ElfHeader;
const ProgramHeader = elf.ProgramHeader;
const PageDirectory = paging.PageDirectory;
const ProcessState = proc.ProcessState;
const IretFrame = idt.IretFrame;
const AuxiliaryVectorValue = elf.AuxiliaryVectorValue;

pub noinline fn execve(buff: usize, size: usize, frame: *IretFrame) isize {
    var path = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    do_execve(path, frame) catch return -1;
    return 0;
}

fn do_execve(path: []const u8, frame: *IretFrame) !void {
    var dentry: *DirEnt = undefined;
    if ((try scheduler.runningProcess.cwd.resolve(path, &dentry)) != .Found)
        return error.NotFound;
    var header: ElfHeader = undefined;
    _ = try dentry.inode.read(std.mem.asBytes(&header), 0);
    try validate_header(&header);
    const phtable = try mem.allocator.alloc(ProgramHeader, header.phnum);
    defer mem.allocator.free(phtable);
    const size = try dentry.inode.read(std.mem.sliceAsBytes(phtable), header.phoff);
    std.debug.assert(size == header.phentsize * header.phnum);
    var brk: usize = 0;
    for (phtable) |entry| {
        if (entry.p_type == .LOAD) {
            try load_entry(entry, dentry);
            if (entry.vaddr + entry.memsz > brk)
                brk = entry.vaddr + entry.memsz;
        }
    }
    // TODO: Probably more things to do, like resetting signal handlers
    scheduler.runningProcess.base_brk = brk;
    scheduler.runningProcess.brk = brk;
    var esp: usize = proc.US_STACK_BASE - 8;
    utils.push(&esp, AuxiliaryVectorValue{ ._type = .NULL, .value = undefined });
    utils.push(&esp, @as(u32, 0));
    utils.push(&esp, @as(u32, 0));
    utils.push(&esp, @as(u32, 0));
    frame.esp = esp;
    frame.eip = header.entry;
}

fn load_entry(entry: ProgramHeader, dentry: *DirEnt) !void {
    var page = std.mem.alignBackward(entry.vaddr, paging.PAGE_SIZE);
    const last_page = std.mem.alignBackward(entry.vaddr + entry.memsz, paging.PAGE_SIZE);

    var file_offset = entry.offset;
    var to_load = entry.filesz;
    var mem_offset = entry.vaddr - page;

    while (page <= last_page) : (page += paging.PAGE_SIZE) {
        try scheduler.runningProcess.pd.allocVirt(page, paging.USER | paging.WRITE);
        const will_load = std.math.min(to_load, paging.PAGE_SIZE - mem_offset);
        var slice = try scheduler.runningProcess.pd.vBufferToPhy(will_load, page + mem_offset);
        if ((try dentry.inode.read(slice, file_offset)) != will_load)
            @panic("Failed to load ELF");
        file_offset += will_load;
        to_load -= will_load;
        mem_offset = 0;
    }
}

fn validate_header(header: *const ElfHeader) !void {
    if (header.ident.version != 1)
        return error.UnsuportedVersion;
    if (header.ident.class != 1)
        return error.UnsuportedClass; // Elf binary is not 32 bits
    if (header.ident.encoding != 1)
        return error.UnsuportedEndianess;
    if (header.e_type != .EXEC)
        return error.NotExecutable;
    if (@sizeOf(ProgramHeader) != header.phentsize)
        return error.InvalidPhentsize;
}
