
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8 = number to convert
;	 r9 = ptr to output buffer

	align 4
toAsciiDec8:
	push	rdx rax rcx rdi rsi rbp rbx

	mov	rax, [rsp + 7*8+8]
	mov	rbp, [rsp + 7*8]
	xor	ecx, ecx
	xor	ebx, ebx

	cmp	eax, 0
	jge	@f
	neg	eax
	mov	byte [rbp], '-'
	add	rbp, 1
@@:
	add	rbp, 9
	not	rbx
	;...



	xor	ebx, ebx
	mov	rsi, 0xcccc'cccc'cccc'cccd
.next_digit:
	mov	rcx, rax
	add	ebx, 1
	mul	rsi

	cmp	ebx, 4
	jnz	@f
	mov	byte [rbp], ','
	mov	ebx, 1
	sub	rbp, 1
@@:
	mov	rdi, rdx
	shr	rdi, 3
	mov	rax, rdi
	lea	rdi, [rdi + rdi*4]
	lea	rdi, [rdi + rdi - '0']
	sub	rcx, rdi
	mov	[rbp], cl
	sub	rbp, 1
	test	rax, rax
	jnz	.next_digit



	pop	rbx rbp rsi rdi rcx rax rdx
	ret	16

;===================================================================================================


; input:  r8 - number
;	  r9 - mem ptr where to save
;	  r12b - how many 4bit digits to process starting with lowest bit in the r8 register

	align 8
regToAsciiHex:
	mov	r13, '01234567'
	mov	r14, '89abcdef'
	push	rax rdi rcx r14 r13
	cld
	mov	rdi, r9

	movzx	ecx, r12b
	shl	ecx, 2
	sub	ecx, 4
	jb	.exit
	ror	r8, cl
@@:
	mov	eax, r8d
	and	eax, 15
	movzx	eax, byte [rsp + rax]
	rol	r8, 4
	stosb
	sub	r12d, 1
	jnz	@b
.exit:
	mov	rcx, [rsp + 16]
	mov	rdi, [rsp + 24]
	mov	rax, [rsp + 32]
	add	rsp, 40
	ret

;===================================================================================================
; input:  r8d - number
; return: xmm0 - 8byte ascii string (unused top bytes are zeroed)
;	  input r8 unchanged

	align 8
r4ToAsiiHex:
	push	rax rcx rsi rdi

	mov	eax, r8d
	mov	ecx, r8d
	shr	eax, 4
	and	ecx, 0xf0f0f0f
	and	eax, 0xf0f0f0f
	mov	esi, ecx
	mov	edi, eax
	add	ecx, 0x76767676 	; 0-9 results in <= 127
	add	eax, 0x76767676 	;  a-f results in 128+
	shr	ecx, 7
	shr	eax, 7
	and	ecx, 0x1010101
	and	eax, 0x1010101
	imul	ecx, 39
	imul	eax, 39
	lea	ecx, [ecx + esi + 0x30303030]
	lea	eax, [eax + edi + 0x30303030]
	movd	xmm0, ecx
	movd	xmm1, eax
	punpcklbw xmm0, xmm1

	pop	rdi rsi rcx rax
	ret

;===================================================================================================
; input:  r8 - number
; return: xmm0 - 16byte ascii string
;	  input r8 unchanged

	align 8
r8ToAsiiHex:
	push	rax rcx

	mov	rax, r8
	mov	rcx, r8
	mov	r13, 0xf0f0f0f'0f0f0f0f
	shr	rax, 4
	and	rcx, r13
	and	rax, r13
	mov	r13, 0x76767676'76767676
	mov	r9, rcx
	mov	r12, rax
	add	rcx, r13
	add	rax, r13
	mov	r13, 0x1010101'01010101
	shr	rcx, 7
	shr	rax, 7
	and	rcx, r13
	and	rax, r13
	mov	r13, 0x30303030'30303030
	imul	rcx, 39
	imul	rax, 39
	add	r9, r13
	add	r12, r13
	add	r9, rcx
	add	r12, rax
	movq	xmm0, r9
	movq	xmm1, r12
	punpcklbw xmm0, xmm1

	pop	rcx rax
	ret

;===================================================================================================
toAsciiDec:
	push	rax rcx rdi rsi rbp rbx
	pop	rbx rbp rsi rdi rcx rax
	ret

toAciiHex:
	ret

toAsciiBin:
	ret

















