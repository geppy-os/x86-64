
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

macro noThreadSw var
{
	mov	eax, 2
	mov	cr8, rax

	; todo: mask lapic timer and check remaining count in resumeThreadSw
	; add mem variable to preserve lapic state to handle nested functions
	;Could check if "var" supplied to apply or not additional logic
}

macro attemptThreadSw{

	; performes thread switch if lapic timer counter reached zero
}

macro resumeThreadSw
{
	xor	eax, eax
	mov	cr8, rax
}