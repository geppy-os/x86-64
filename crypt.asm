
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;get 2ybes, and for each bit: bit set - run one hash algo, bit cleared - run another hash algo
; hash is run on separate set of bytes

; If user not moving mouse then use TSC - next best thing low bits of a fast timer


;===================================================================================================
;     rand_tsc	   /////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; return: r8 - 2byte random value

	align 4
rand_tsc:
	push	rax rdx rcx rsi

	rdtsc
	mov	esi, edx
	shl	rsi, 32
	or	rax, rsi

	movzx	ecx, byte [tscGranul]
	shr	rax, cl

	xor	edx, edx
	movzx	ecx, byte [tscGranul + 4]
	cmp	ecx, 1
	jbe	@f
	div	rcx
@@:
	mov	ecx, eax
	shr	rax, 2
	and	ecx, 11b
	mov	rsi, rax
	ror	eax, cl

	mov	ecx, eax
	shr	ecx, 16
	mul	cx

	shr	rsi, 32
	xor	eax, esi
	movzx	r8d, ax

	pop	rsi rcx rdx rax
	ret

;===================================================================================================
;     tsc     //////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; TSC may count in certain intervals so that a few low bit are unchanged, we need to get rid of
; these bits with min casualties - without loosing higher bits.
; Preserves all registers, including flags
; Result is saved into 1byte "tscGranul" var

	align 4
tsc:
	pushf
	push	rax rcx rdx rsi rdi rbp
	pushq	0 0

	mov	rdi, rsp
	mov	ebp, 8
@@:	cld
	xor	ecx, ecx
	bt	eax, 3
	adc	ecx, 0
	and	eax, 7
	shl	ecx, 31
	or	eax, ecx
	cpuid
	mov	rax, cr0
	rdtsc				; not exactly bad that RDTSC executed in predictable intervals
	stosb				;    TODO: "tsc" function is run several times anyway
	sub	ebp, 1
	jnz	@b

;---------------------------------------------------------------------------------------------------

	mov	rsi, rsp
	lodsb
	mov	edi, 7
	mov	ebp, 1
	and	eax, 11b
	mov	ecx, eax
.test4:
	lodsb
	and	eax, 11b
	xor	eax, ecx
	neg	eax
	sbb	edi, 0
	add	ebp, 1
	cmp	ebp, 8
	jb	.test4

	;--------------------------------
	cmp	edi, 7
	jnz	@f
	mov	byte [tscGranul], 2	; shift by 2 bits
	jmp	.check_other_bits

;---------------------------------------------------------------------------------------------------
@@:
	mov	rsi, rsp
	lodsb
	mov	edi, 7
	mov	ebp, 1
	and	eax, 1b
	mov	ecx, eax
.test2:
	lodsb
	and	eax, 1b
	xor	eax, ecx
	neg	eax
	sbb	edi, 0
	add	ebp, 1
	cmp	ebp, 8
	jb	.test2

	;--------------------------------
	cmp	edi, 7
	jnz	.check_other_bits
	mov	byte [tscGranul], 1	; shift by 1 bit

;---------------------------------------------------------------------------------------------------
.check_other_bits:






.done:
	add	rsp, 16
	pop	rbp rdi rsi rdx rcx rax
	popf
	ret


