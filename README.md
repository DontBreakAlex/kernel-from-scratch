# Kernel from Scratch

This is my unix-like kernel. The end goal is to be able to compile and run most programs made for linux on it.

## Screenshots

![screenshot](/screenshot.png?raw=true "A basic shell running using my kernel")

## Features

- Virtual Memory
- Cooperative Multitasking with IPC
- Userspace with privileges and syscalls
- VFS with a buffer cache, dcache and icache
- Ext2 driver