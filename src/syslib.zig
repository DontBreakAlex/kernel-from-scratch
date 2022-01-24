pub fn read(fd: usize, buffer: []u8, count: usize) isize {
    return asm volatile (
        \\mov $0, %%eax
        \\int $0x80
        : [ret] "={eax}" (-> isize),
        : [fd] "{ebx}" (fd),
          [buf] "{ecx}" (buffer.ptr),
          [cnt] "{edx}" (count),
    );
}
