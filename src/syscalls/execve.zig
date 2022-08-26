const std = @import("std");
const scheduler = @import("../scheduler.zig");
const elf = @import("../elf.zig");
const tty = @import("../tty.zig");
const mem = @import("../memory/mem.zig");
const serial = @import("../serial.zig");

const DirEnt = @import("../io/dirent.zig").DirEnt;
const ElfHeader = elf.ElfHeader;
const ProgramHeader = elf.ProgramHeader;

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
    const size = try dentry.inode.read(std.mem.sliceAsBytes(phtable), header.phoff);
    serial.format("{} {}\n", .{ size, header.phentsize * header.phnum });
    for (phtable) |ent|
        serial.format("{x}\n", .{ ent });
    // serial.format("{*}\n", .{ std.mem.sliceAsBytes(phtable) });
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