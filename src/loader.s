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
resb 65536
global stack_top
stack_top:

section .text

extern kernel_main

global _start:function (_start.end - _start)
_start:
	mov esp, stack_top
	cli ; We don't want any interrupt while seting the GDT
	lgdt [gdtr_descr]
	; Enable SSE
	mov eax, cr0
	and ax, 0xFFFB
	or ax, 0x2
	mov cr0, eax
	mov eax, cr4
	or ax, 3 << 9
	mov cr4, eax
	jmp 0x08:.setcs; Far jump to the label, switch to the code segment of the new GDT

	.setcs:
	mov ax, 0x10 ; Data segment
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ax, 0x18
	mov ss, ax

	call kernel_main

.hang:
	hlt
	jmp .hang
.end:

section .gdt

gdt_start:
gdt_null:	; Null entry
	dd 0x0	; dd means Define Double word (32 bits)
	dd 0x0
k_code:	; Code segment
	; Segment Base Address (base) = 0x0
	; Segment Limit (limit) = 0xfffff
	; These pointers are split up all around the data structure to allow
	; the gdt to be backwards compatible with the 80286 (old intel processor)
	dw 0xffff	; Limit bits 0-15
	dw 0x0000	; Base bits 0-15
	db 0x00		; Base bits 16-23
	; Flag Set 1:
		; Segment Present: 0b1
		; Descriptor Privilege level: 0x00 (ring 0)
		; Descriptor Type: 0b1 (code/data)
	; Flag Set 2: Type Field
		; Code: 0b1 (this is a code segment)
		; Conforming: 0b0 (Code w/ lower privilege may not call this)
		; Readable: 0b1 (Readable => can read code constants)
		; Accessed: 0b0 (Used for debugging and virtual memory. CPU sets bit when accessing segment)
	db 10011010b	; Flag set 1 and 2 form the "Access Byte"
	; Flag Set 3
		; Granularity: 0b1 (Set to 1 multiplies limit by 4K. Shift 0xfffff 3 bytes left, allowing to span full 32G of memory)
		; Size: 0b1 (32 bit segment, of not set 16 bit segment)
		; Long mode: 0b0 (For 64 bit segments)
		; Unused: 0b0
	db 11001111b	; Flag set 3 and limit bits 16-19
	db 0x00		; Base bits 24-31
k_data:
	; Same except for code flag:
		; Code: 0b0
	dw 0xffff	; Limit bits 0-15
	dw 0x0000	; Base bits 0-15
	db 0x00		; Base bits 16-23
	db 10010010b	; Flag set 1 and 2
	db 11001111b	; 2nd flags and limit bits 16-19
	db 0x00		; Base bits 24-31
k_stack:
	dw 0xffff
	dw 0x0000
	db 0x00
	db 10010010b
	db 11001111b
	db 0x00
u_code:
	dw 0xffff
	dw 0x0000
	db 0x00
	db 11111010b
	db 11001111b
	db 0x00
u_data:
	dw 0xffff
	dw 0x0000
	db 0x00
	db 11110010b
	db 11001111b
	db 0x00
u_stack:
	dw 0xffff
	dw 0x0000
	db 0x00
	db 11110010b
	db 11001111b
	db 0x00

gdt_end:

gdtr_descr :
  dw gdt_end - gdt_start - 1
  dd gdt_start
