NAME	= kernel.bin

ASM_SRC	= loader.s idt.s
ASM_OBJ	= $(ASM_SRC:%.s=obj/%.o)

all:	$(NAME)

$(NAME): $(ASM_OBJ) src/kernel_main.zig src/idt.zig
	zig build-exe src/kernel_main.zig $(ASM_OBJ) -target i386-freestanding -T linker.ld -femit-bin=$(NAME) -O ReleaseFast

$(ASM_OBJ): obj/%.o : src/%.s
	nasm -felf32 -o $@ $<

grub.iso: $(NAME)
	cp $(NAME) iso/boot/kernel
	grub-mkrescue -o grub.iso iso

clean:
	rm -rf src/zig-cache
	rm -f *.o obj/*.o

fclean:	clean
	rm -f kernel.bin grub.iso

re:		fclean all

fmt:
	zig fmt src/kernel_main.zig src/idt.zig

.PHONY:	all clean fclean fmt
