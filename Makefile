NAME	= kernel.bin

ASM_SRC	= loader.s idt.s
ASM_OBJ	= $(ASM_SRC:%.s=obj/%.o)

ZIG_SRC	= src/kernel_main.zig src/idt.zig src/vga.zig src/pic.zig src/utils.zig src/keyboard.zig src/keyboard_map.zig src/shell.zig src/cursor.zig src/commands.zig src/multiboot.zig src/elf.zig src/memory.zig
ZIG		= zig
PWD		= $(shell pwd)

all:	$(NAME)

$(NAME): $(ASM_OBJ) $(ZIG_SRC)
	$(ZIG) build-exe src/kernel_main.zig $(ASM_OBJ) -target i386-freestanding -T linker.ld -mno-red-zone -femit-bin=$(NAME) -O Debug

$(ASM_OBJ): obj/%.o : src/%.s
	nasm -felf32 -o $@ $<

grub.iso: $(NAME)
	cp $(NAME) iso/boot/kernel
	grub-mkrescue -o grub.iso iso || docker run --rm -v $(PWD):/mount kfs-build grub-mkrescue -o grub.iso iso

clean:
	rm -rf src/zig-cache
	rm -f *.o obj/*.o

fclean:	clean
	rm -f kernel.bin grub.iso

re:		fclean all

fmt:
	zig fmt $(ZIG_SRC)

.PHONY:	all clean fclean fmt
