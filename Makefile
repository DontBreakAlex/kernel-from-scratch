NAME	= kernel.bin

ASM_SRC	= loader.s idt.s
ASM_OBJ	= $(ASM_SRC:%.s=obj/%.o)

ZIG_SRC := $(shell find src/ -maxdepth 2 -type f -name "*.zig")
ZIG		= zig
PWD		= $(shell pwd)

all:	$(NAME)

$(NAME): $(ASM_OBJ) $(ZIG_SRC)
	$(ZIG) build-exe src/kernel_main.zig $(ASM_OBJ) -target i386-freestanding -T linker.ld -mno-red-zone -femit-bin=$(NAME) -O Debug

$(ASM_OBJ): obj/%.o : src/%.s
	nasm -felf32 -o $@ $<

grub.iso: $(NAME)
	cp $(NAME) iso/boot/kernel
	grub-mkrescue -o grub.iso iso || docker run --rm -v $(PWD):/mount ghcr.io/dontbreakalex/kfs-build grub-mkrescue -o grub.iso iso

qemu: grub.iso
	qemu-system-i386 -s -drive file=grub.iso,format=raw -serial stdio -drive file=ext.img,format=raw

clean:
	rm -rf src/zig-cache
	rm -f *.o obj/*.o

fclean:	clean
	rm -f kernel.bin grub.iso

re:		fclean all

fmt:
	zig fmt $(ZIG_SRC)

.PHONY:	all clean fclean fmt qemu
