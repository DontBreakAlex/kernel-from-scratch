NAME	= kernel.bin

all:	$(NAME)

$(NAME):	loader.o gdt.o kernel_main.o
	ld -melf_i386 -T linker.ld -o kernel.bin gdt.o loader.o kernel_main.o

loader.o: loader.s
	nasm -felf32 loader.s -o loader.o

gdt.o: src/gdt.s
	nasm -felf32 src/gdt.s -o gdt.o

kernel_main.o: src/kernel_main.zig
	zig build-obj -target i386-freestanding src/kernel_main.zig

grub.iso:
	grub-mkrescue -o grub.iso iso

clean:
	rm -rf src/zig-cache
	rm -f *.o

fclean:	clean
	rm -f kernel.bin

re:		fclean all

fmt:
	zig fmt src/kernel_main.zig

.PHONY:	all clean fclean fmt
