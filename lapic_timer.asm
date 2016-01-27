
  align 8
int_lapicTimer:
	pushf

	add	byte [qword 0], 1


	popf
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq
	; rip
	; cs
	; rflags