const utils = @import("utils.zig");
const Buffer = utils.Buffer;

pub const FileDescriptor = union(enum) {
    SimpleReadable: *Buffer,
    PipeIn: *Buffer,
    PipeOut: *Buffer,

    pub fn isReadable(self: FileDescriptor) bool {
        return switch (self) {
            .SimpleReadable => true,
            .PipeOut => true,
            .PipeIn => false,
        };
    }

    pub fn readableLength(self: FileDescriptor) usize {
        return switch (self) {
            .SimpleReadable => |buffer| buffer.readableLength(),
            .PipeOut => |buffer| buffer.readableLength(),
            .PipeIn => unreachable,
        };
    }

    pub fn read(self: FileDescriptor, dst: []u8) usize {
        return switch (self) {
            .SimpleReadable => |buffer| buffer.read(dst),
            .PipeOut => |buffer| buffer.read(dst),
            .PipeIn => unreachable,
        };
    }

    pub fn write(self: FileDescriptor, src: []const u8) !void {
        return switch (self) {
            .SimpleReadable => |buffer| buffer.write(src),
            .PipeOut => |buffer| buffer.write(src),
            .PipeIn => unreachable,
        };
    }
};
