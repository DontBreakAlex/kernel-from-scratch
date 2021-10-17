NAME	= kernel.bin

all:	$(NAME)

$(NAME):	loader.o
	ld -melf_i386 -T linker.ld -o kernel.bin loader.o kernel_main.o

loader.o:
	nasm -felf32 loader.s

kernel_main.o:
	zig build-obj  -target i386-freestanding src/kernel_main.zig
