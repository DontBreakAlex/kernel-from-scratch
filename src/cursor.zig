const vga = @import("vga.zig");
const utils = @import("utils.zig");

const VGA_WIDTH = vga.VGA_WIDTH;
const VGA_HEIGHT = vga.VGA_HEIGHT;
const CURSOR_CMD = 0x03D4;
const CURSOR_DATA = 0x03D5;

pub const Cursor = struct {
    x: usize,
    y: usize,

    fn left(self: *Cursor) void {
        if (self.x == 0) {
            if (self.up()) {
                self.x = VGA_WIDTH - 1;
            }
        } else {
            self.x -= 1;
        }
    }
    fn right(self: *Cursor) void {
        if (self.x + 1 == VGA_WIDTH) {
            self.x = 0;
            self.down();
        } else {
            self.x += 1;
        }
    }
    fn down(self: *Cursor) void {
        if (self.y + 1 == VGA_HEIGHT) {
            vga.shiftVga();
        } else {
            self.y += 1;
        }
    }
    fn up(self: *Cursor) bool {
        if (self.y == 0)
            return false;
        self.y -= 1;
        return true;
    }
    pub fn goto(self: *Cursor, x: u8, y: u8) void {
        self.x = x;
        self.y = y;
    }
    fn update(self: Cursor) void {
        const cursor = self.x + self.y * VGA_WIDTH;
        utils.out(CURSOR_CMD, @as(u8, 0x0F));
        utils.out(CURSOR_DATA, @truncate(u8, (cursor & 0xFF)));
        utils.out(CURSOR_CMD, @as(u8, 0x0E));
        utils.out(CURSOR_DATA, @truncate(u8, (cursor >> 8 & 0xFF)));
    }
    pub fn reset(self: *Cursor) void {
        self.goto(0, 0);
        self.update();
    }
    pub fn move(self: *Cursor, x: u8, y: u8) void {
        self.goto(x, y);
        self.update();
    }
    pub fn forward(self: *Cursor) void {
        self.right();
        self.update();
    }
    pub fn backward(self: *Cursor) void {
        self.left();
        self.update();
    }
    pub fn downward(self: *Cursor) void {
        self.down();
        self.update();
    }
    pub fn upward(self: *Cursor) void {
        self.up();
        self.update();
    }
    pub fn newline(self: *Cursor) void {
        self.x = 0;
        self.downward();
    }
    pub fn index(self: Cursor) usize {
        return self.y * VGA_WIDTH + self.x;
    }
    pub fn enable() void {
        utils.out(CURSOR_CMD, @as(u8, 0x0A));
        utils.out(CURSOR_DATA, (utils.in(u8, CURSOR_DATA) & 0xC0) | 14);
        utils.out(CURSOR_CMD, @as(u8, 0x0B));
        utils.out(CURSOR_DATA, (utils.in(u8, CURSOR_DATA) & 0xE0) | 15);
    }
    pub fn save(self: Cursor) Cursor {
        return self;
    }
    pub fn restore(self: *Cursor, saved: Cursor) void {
        self.* = saved;
        self.update();
    }
};
