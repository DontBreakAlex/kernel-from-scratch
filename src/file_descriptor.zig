const utils = @import("utils.zig");
const mem = @import("memory/mem.zig");
const scheduler = @import("scheduler.zig");
const Buffer = utils.Buffer;
const Event = scheduler.Event;

pub const FileDescriptor = union(enum) {
    SimpleReadable: *Buffer,
    PipeIn: *Pipe,
    PipeOut: *Pipe,
    Closed,

    pub fn isReadable(self: FileDescriptor) bool {
        return switch (self) {
            .SimpleReadable => true,
            .PipeOut => true,
            .PipeIn => false,
            .Closed => unreachable,
        };
    }

    pub fn isWritable(self: FileDescriptor) bool {
        return switch (self) {
            .SimpleReadable => false,
            .PipeOut => false,
            .PipeIn => true,
            .Closed => unreachable,
        };
    }

    pub fn readableLength(self: FileDescriptor) usize {
        return switch (self) {
            .SimpleReadable => |buffer| buffer.readableLength(),
            .PipeOut => |pipe| pipe.buffer.readableLength(),
            .PipeIn => unreachable,
            .Closed => unreachable,
        };
    }

    pub fn writableLength(self: FileDescriptor) usize {
        return switch (self) {
            .SimpleReadable => |buffer| buffer.writableLength(),
            .PipeOut => unreachable,
            .PipeIn => |pipe| pipe.buffer.writableLength(),
            .Closed => unreachable,
        };
    }

    pub fn read(self: FileDescriptor, dst: []u8) usize {
        return switch (self) {
            .SimpleReadable => |buffer| buffer.read(dst),
            .PipeOut => |pipe| pipe.buffer.read(dst),
            .PipeIn => unreachable,
            .Closed => unreachable,
        };
    }

    pub fn write(self: FileDescriptor, src: []const u8) !void {
        return switch (self) {
            .SimpleReadable => |buffer| buffer.write(src),
            .PipeOut => unreachable,
            .PipeIn => |pipe| pipe.buffer.write(src),
            .Closed => unreachable,
        };
    }

    pub fn dup(self: *FileDescriptor) void {
        switch (self.*) {
            .SimpleReadable, .Closed => {},
            .PipeIn, .PipeOut => |pipe| pipe.refcount += 1,
        }
    }

    pub fn close(self: *FileDescriptor) void {
        switch (self.*) {
            .SimpleReadable, .Closed => {},
            .PipeIn, .PipeOut => |pipe| {
                pipe.refcount -= 1;
                if (pipe.refcount == 0) {
                    mem.allocator.destroy(pipe);
                }
            },
        }
        self.* = .Closed;
    }

    pub fn event(self: FileDescriptor) Event {
        return switch (self) {
            .SimpleReadable => Event{ .IO = self },
            .PipeIn => Event{ .IO = FileDescriptor{ .PipeOut = self.PipeIn } },
            .PipeOut => Event{ .IO = FileDescriptor{ .PipeIn = self.PipeOut } },
            .Closed => unreachable,
        };
    }
};

pub const Pipe = struct {
    refcount: usize = 0,
    buffer: Buffer = Buffer.init(),
};
