pub const Ext2Header = packed struct {
    /// Total number of inodes
    inodes_count: u32,
    /// Total number of blocks
    blocks_count: u32,
    /// Total number of blocks reserved for the superuser
    r_blocks_count: u32,
    /// Number of free blocks, including reserved ones
    free_blocks_count: u32,
    /// Number of free inodes
    free_inodes_count: u32,
    /// Id of the block containing the superblock structure
    first_data_block: u32,
    /// block_size = 1024 << log_block_size
    log_block_size: u32,
    /// if( positive )
    ///     fragmnet size = 1024 << s_log_frag_size;
    /// else
    ///     framgnet size = 1024 >> -s_log_frag_size;
    log_frag_size: u32,
    /// Number of blocks per group
    blocks_per_group: u32,
    /// Number of fragments per group
    frags_per_group: u32,
    /// Number of inodes per group
    inodes_per_group: u32,
    /// Last mount (Unix time)
    mtime: u32,
    /// Last write (Unix time)
    wtime: u32,
    /// Number of mounts since last full check
    mnt_count: u16,
    /// Number of mounts between full checks
    max_mnt_count: u16,
    /// Magic value identifying the file system as ext2 (0xEF53).
    magic: u16,
    /// File system state
    /// 1 => Unmounted cleanly
    /// 2 => Errors detected (Unproperly unmounted)
    state: u16,
    /// What to do when an error is detected
    /// 1 => Ignore
    /// 2 => Remount read-only
    /// 3 => Kernel panic
    errors: u16,
    /// Minor revison level
    minor_rev_level: u16,
    /// Last file system check (Unix time)
    last_check: u32,
    /// Intervel between full checks (Unix time)
    checkinterval: u32,
    /// Indentifier of the OS that created the FS
    /// 0 => Linux
    /// 1 => Hurd
    /// 2 => Masix
    /// 3 => FreeBSD
    /// 4 => Lites
    creator_os: u32,
    /// Revision level
    /// 0 => Old
    /// 1 => Dynamic
    rev_level: u32,
    /// Default user id for reserved blocks
    def_resuid: u16,
    /// Default group id for resered blocks
    def_resguid: u16,
    /// First usable inode for standard files
    first_ino: u32,
    /// Size of the inode structure
    inode_size: u16,
    /// Block group number hosting the superblock structure
    block_group_nr: u16,
    /// Feature compatibility bitmask
    feature_compat: u32,
    /// Feature incompatibility bitmask
    feature_incompat: u32,
    /// Read-only features bitmask
    feature_ro_compat: u32,
    uuid1: u64,
    uuid2: u64,
};

// TODO:
// -> Create a buffer cache
// -> Add checks for ext2 version
// -> Create a structure with:
//    -> The superblock structure
//    -> The block group descriptor table