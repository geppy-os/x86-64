
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


	align 8
lapicT_calcSpeed:
	push	rax rcx rdx rsi rdi rbp

	mov	esi, lapicT_ticks
	mov	eax, [rsi]
	mov	ecx, [rsi + 4]
	mov	edi, [rsi + 8]
	mov	ebp, [rsi + 12]
	mov	esi, [rsi + 16]
	neg	eax
	neg	ecx
	neg	edi
	neg	ebp
	neg	esi
	add	rax, rcx
	add	rdi, rbp
	add	rax, rsi
	add	rax, rdi

	imul	rax, 10

	xor	edx, edx
	mov	edi, 5
	div	rdi

	imul	rax, 1000000

	mov	edi, 1953125 * 10
	xor	edx, edx
	div	rdi		; eax = number of lapicT ticks each millisecond for the divider of 2

	xor	edi, edi
	not	edi
	mov	rsi, rdx
	cmp	rax, rdi
	ja	k64err
	cmp	rsi, rdi
	ja	k64err

	shl	rsi, 32
	or	rax, rsi
	mov	[lapicT_ms], rax

	pop	rbp rdi rsi rdx rcx rax
	ret