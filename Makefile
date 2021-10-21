NAME	= kernel.bin

ASM_SRC	= loader.s gdt.s idt.s
ASM_OBJ	= $(ASM_SRC:%.s=obj/%.o)

all:	$(NAME)

$(NAME): $(ASM_OBJ) kernel_main.o
	ld -melf_i386 -T linker.ld -o kernel.bin $(ASM_OBJ) kernel_main.o

$(ASM_OBJ): obj/%.o : src/%.s
	nasm -felf32 -o $@ $<

kernel_main.o: src/kernel_main.zig
	zig build-obj -target i386-freestanding -O ReleaseSafe src/kernel_main.zig

grub.iso:
	grub-mkrescue -o grub.iso iso

clean:
	rm -rf src/zig-cache
	rm -f *.o

fclean:	clean
	rm -f kernel.bin

re:		fclean all

fmt:
	zig fmt src/kernel_main.zig src/idt.zig

.PHONY:	all clean fclean fmt
