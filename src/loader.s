MBALIGN  equ  1 << 0
MEMINFO  equ  1 << 1
FLAGS    equ  MBALIGN | MEMINFO
MAGIC    equ  0x1BADB002
CHECKSUM equ -(MAGIC + FLAGS)

section .multiboot
align 4
	dd MAGIC
	dd FLAGS
	dd CHECKSUM

section .bss
align 16
stack_bottom:
resb 32768
stack_top:

section .text

extern gdt_descriptor
extern CODE_SEG
extern DATA_SEG
extern kernel_main
extern IDT_PTR

global _start:function (_start.end - _start)
_start:
	cli ; We don't want any interrupt while seting the GDT
	lgdt [gdt_descriptor]
	jmp CODE_SEG:.setcs; Far jump to the label, switch to the code segment of the new GDT

	.setcs:
	mov ax, DATA_SEG
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax
	mov esp, stack_top

	call kernel_main

	call boch_break
	sti
	int 4

	cli
.hang:
	hlt
	jmp .hang
.end:

global boch_break
boch_break:
	xchg bx, bx
	ret

global load_idt
load_idt:
	mov edx, [esp + 4]
	lidt [edx]
	ret
