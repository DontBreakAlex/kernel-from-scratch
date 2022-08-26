const std = @import("std");
const scheduler = @import("../scheduler.zig");
const elf = @import("../elf.zig");
const tty = @import("../tty.zig");
const mem = @import("../memory/mem.zig");
const serial = @import("../serial.zig");
const paging = @import("../memory/paging.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const ElfHeader = elf.ElfHeader;
const ProgramHeader = elf.ProgramHeader;
const PageDirectory = paging.PageDirectory;

pub noinline fn execve(buff: usize, size: usize) isize {
    var path = scheduler.runningProcess.pd.vBufferToPhy(size, buff) catch return -1;
    do_execve(path) catch return -1;
    return 0;
}

fn do_execve(path: []const u8) !void {
    var dentry: *DirEnt = undefined;
    if ((try scheduler.runningProcess.cwd.resolve(path, &dentry)) != .Found)
        return error.NotFound;
    var header: ElfHeader = undefined;
    _ = try dentry.inode.read(std.mem.asBytes(&header), 0);
    try validate_header(&header);
    // serial.format("{s}", .{ header });
    const phtable = try mem.allocator.alloc(ProgramHeader, header.phnum);
    defer mem.allocator.free(phtable);
    const size = try dentry.inode.read(std.mem.sliceAsBytes(phtable), header.phoff);
    serial.format("{} {}\n", .{ size, header.phentsize * header.phnum });
    var new_cr3 = try PageDirectory.init();
    errdefer new_cr3.deinit();
    for (phtable) |entry| {
        // serial.format("{x}\n", .{ ent });
        if (entry.p_type == .LOAD) {
            // TODO: Alloc correct size
            try new_cr3.allocVirt(entry.vaddr, paging.USER);
            var slice = try new_cr3.vBufferToPhy(entry.filesz, entry.vaddr);
            try dentry.inode.read(slice, entry.offset);
        }
    }
    scheduler.runningProcess.pd.deinit();
    // TODO: Probably more things to do, like resetting signal handlers
    scheduler.runningProcess.pd = new_cr3;
    process.state = .{ .SavedState = ProcessState{
        .cr3 = @ptrToInt(process.pd.cr3),
        .esp = US_STACK_BASE - 4,
        .regs = 0,
    } };
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