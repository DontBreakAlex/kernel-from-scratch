; GDT - Global Descriptor Table
global gdt_descriptor
global CODE_SEG
global DATA_SEG

gdt_start:
gdt_null:	; Null entry
	dd 0x0	; dd means Define Double word (32 bits)
	dd 0x0
gdt_code:	; Code segment
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
gdt_data:
	; Same except for code flag:
		; Code: 0b0
	dw 0xffff	; Limit bits 0-15
	dw 0x0000	; Base bits 0-15
	db 0x00		; Base bits 16-23
	db 10010010b	; Flag set 1 and 2
	db 11001111b	; 2nd flags and limit bits 16-19
	db 0x00		; Base bits 24-31

gdt_end:		; Needed to calculate GDT size for inclusion in GDT descriptor

; GDT Descriptor
gdt_descriptor:
	dw gdt_end - gdt_start - 1	; This subtraction occurs because the maximum value of Size is 65535,
	dd gdt_start				; while the GDT can be up to 65536 bytes in length (8192 entries).
								; Further, no GDT can have a size of 0 bytes.

; Define constants
CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start
