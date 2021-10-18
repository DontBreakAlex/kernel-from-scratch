const VgaEntryColor = u8;
const VgaEntry = u16;

const VgaColor = enum(u8) {
    BLACK = 0,
    BLUE = 1,
    GREEN = 2,
    CYAN = 3,
    RED = 4,
    MAGENTA = 5,
    BROWN = 6,
    LIGHT_GREY = 7,
    DARK_GREY = 8,
    LIGHT_BLUE = 9,
    LIGHT_GREEN = 10,
    LIGHT_CYAN = 11,
    LIGHT_RED = 12,
    LIGHT_MAGENTA = 13,
    LIGHT_BROWN = 14,
    WHITE = 15,
};

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;

const VGA_BUFFER = @intToPtr([*]volatile VgaEntry, 0xB8000);

inline fn vgaEntryColor(foreground: VgaColor, background: VgaColor) VgaEntryColor {
    return @enumToInt(foreground) | @enumToInt(background) << 4;
}

inline fn vgaEntry(character: u8, color: VgaEntryColor) VgaEntry {
    return @intCast(u16, character) | @intCast(u16, color) << 8;
}

fn initalize() void {
    var i: usize = 0;
    const color = vgaEntryColor(VgaColor.LIGHT_GREY, VgaColor.BLACK);
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 1) {
        VGA_BUFFER[i] = vgaEntry(' ', color);
    }
}

export fn kernel_main() void {
    initalize();

    const color = vgaEntryColor(VgaColor.LIGHT_GREY, VgaColor.BLACK);
    var i: usize = 0;
    for ("Hello world !") |c| {
        VGA_BUFFER[i] = vgaEntry(c, color);
        i += 1;
    }
}
