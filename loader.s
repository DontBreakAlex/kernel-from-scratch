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
resb 16384 ; 16 KiB
stack_top:

section .text

extern gdt_descriptor
extern CODE_SEG
extern kernel_main

global _start:function (_start.end - _start)
_start:
	cli ; We don't want any interrupt while seting the GDT
	lgdt [gdt_descriptor]
	jmp CODE_SEG:.flush_pipeline ; Far jump to the label, switch to the code segment of the new GDT

.flush_pipeline:
	mov esp, stack_top

	call kernel_main

	cli
.hang:
	hlt
	jmp .hang
.end:
