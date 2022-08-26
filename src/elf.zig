pub const ElfSectionHeader = packed struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u32,
    sh_addr: u32,
    sh_offset: u32,
    sh_size: u32,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u32,
    sh_entsize: u32,
};

pub const ElfSymtabEntry = struct {
    st_name: u32,
    st_value: u32,
    st_size: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
};

pub const ElfSections = packed struct { num: u32, size: u32, addr: [*]ElfSectionHeader, shndx: u32 };

pub const ElfIdentifier = packed struct {
    /// 0x7F 'E' 'L' 'F'
    magic: [4]u8,
    /// File class
    class: u8,
    /// Data encoding
    encoding: u8,
    /// File version
    version: u8,
    pading: u8,
    pading2: [8]u8,
};

pub const ElfHeader = packed struct {
    ident: ElfIdentifier,
    e_type: ObjectFileType,
    /// Processor type
    machine: u16,
    /// Object file version
    version: u32,
    /// Virtual address of the program entry point
    entry: u32, 
    /// Offset of the program header table
    phoff: u32,
    /// Offset of the section header table
    shoff: u32,
    /// Processor-specific flags
    flags: u32,
    /// Size of the elf header (in bytes)
    ehsize: u16,
    /// Size of program a header table entry in bytes
    phentsize: u16,
    /// Number of entries in the program header table
    phnum: u16,
    /// Size of section a header table entry in bytes
    shentsize: u16,
    /// Number of entries in the section header table
    shnum: u16,
    /// Section header index of the string table
    shstrndx: u16,
};

pub const ObjectFileType = enum(u16) {
    NONE = 0,
    REL = 1,
    EXEC = 2,
    DYN = 3,
    CORE = 4,
};

pub const SegmentType = enum(u32) {
    NULL = 0,
    LOAD = 1,
    DYNAMIC = 2,
    INTERP = 3,
    NOTE = 4,
    SHLIB = 5,
    PHDR = 6,
    _
};

pub const ProgramHeader = packed struct {
    /// Type of segment
    p_type: SegmentType,
    /// Offset of the first byte of the segment in the file
    offset: u32,
    /// Virtual address of the first byte of the segment
    vaddr: u32,
    /// Physical address (not used)
    paddr: u32,
    /// Size of the segment in bytes (could be zero)
    filesz: u32,
    /// Size fo the segment in memory (could be zero)
    memsz: u32,
    flags: u32,
    p_align: u32 
};