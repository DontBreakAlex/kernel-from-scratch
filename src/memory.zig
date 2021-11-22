const PageEntry = packed struct {
    present: u1,
    /// 0 = ro, 1 = rw
    write: u1,
    /// 0 = supervisor only, 1 = public
    user: u1,
    /// 1 = disable write cache
    pwt: u1,
    /// 1 = disable cache
    pcd: u1,
    accessed: u1,
    dirty: u1,
    /// 0 = 4Kib, 1 = 4Mib. Set to 0
    size: u1,
    available: u4,
    phy_addr: u20,
};