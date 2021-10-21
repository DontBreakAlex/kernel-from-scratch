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

extern kernel_main

global _start:function (_start.end - _start)
_start:
	cli ; We don't want any interrupt while seting the GDT
	lgdt [gdtr_descr]
	; mov eax, cr0
	; or eax, 1
	; mov cr0, eax
	jmp 8:.setcs; Far jump to the label, switch to the code segment of the new GDT

	.setcs:
	mov ax, 0x10 ; Data segment
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

section .data
;
; global descriptor table
;
gdt_start:
   ;
   ; null descriptor
   ;
   dd 0
   dd 0
   ;
   ; code descriptor - offset 8
   ;
   dw 0xFFFF      ;[lowest byte of mem]
   dw 0x0         ;[lowest next byte(base)]
   db 0x0         ;[lowest base addres(middle, base)]
   db 10011010b      ;[segment permissions look at sec,2]
   db 11001111b       ;[granuality]"alighment" data at sec,3]
   db 0         ;[high base]
   ;
   ; data descriptor offset 0x10
   ;
   dw 0xFFFF      ;Same!
   dw 0x0         ;Same!
   db 0x0         ;Same!
   db 10010010b      ;only type bit different
   db 11001111b      ;Same!
   db 0         ;Same!
gdt_end :
;
; load into gdtr with ldgt [gdtr_descr] later
;
gdtr_descr :
  dw gdt_end - gdt_start - 1
  dd gdt_start
