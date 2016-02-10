
;---------------------------------------------------------------------------------------------------
; Distributed under GPL v1 License
; All Rights Reserved.
;---------------------------------------------------------------------------------------------------



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
	imul	ecx, 7
	imul	eax, 7
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
	imul	rcx, 7
	imul	rax, 7
	add	r9, r13
	add	r12, r13
	add	r9, rcx
	add	r12, rax
	movq	xmm0, r9
	movq	xmm1, r12
	punpcklbw xmm0, xmm1

	pop	rcx rax
	ret

; hex editor: get max width of all:   00 01 .. fe ff
;	      divide max width in half - this will be separator (space betw bytes)
