ENTRY(_start)

SECTIONS
{
    .multiboot :
        {
            KEEP(*(.multiboot))
        }

	.tss 0x800 : {
		KEEP(*(.tss))
	}

    kbegin = .;
	.text : ALIGN(4K)
	{
		*(.text)
	}

	.rodata : ALIGN(4K) /* Read-only data */
	{
		*(.rodata)
	}

	.data : ALIGN(4K) /* Initialized read-write data */
	{
		*(.data)
	}

	.bss : ALIGN(4K) /* Unitialized read-write data */
	{
		*(COMMON)
		*(.bss)
	}

    kend = .;
}