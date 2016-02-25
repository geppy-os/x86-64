
macro listIsaDevs{

	mov	rsi, isaDevs
	mov	ecx, 16
@@:
	mov	eax, [rsi]
	movzx	ebx, byte [rsi+11]
	movzx	edi, byte [rsi+12]
	reg	rax, 84f
	reg	rbx, 24f
	reg	rdi, 24f

	add	rsi, 20
	sub	ecx, 1
	jnz	@b
}

macro attemptThreadSw{

	; also can perform thread switch if lapic timer counter reached zero
}

