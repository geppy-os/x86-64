
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
; input:  r8 - pointer to user data
;	      (+0 x, +2 y, +4 unsigned length, +6 font id, +8 color,
;		    +12 byte !=0 if fully transparent, +13 byte=0, +14 8byte text pointer)
;	  r9 - pointer to destination DRABUFF struct
;---------------------------------------------------------------------------------------------------
; all input coordinates are signed 2byte values
; DRAWBUFF clipping coordinates are assumed to be signed positive 4byte values, right>=left, bottom>=top
;---------------------------------------------------------------------------------------------------


	align 8
txtOut_noClip:
	push	r15
	sub	rsp, 24

	cld

	movzx	ecx, word [r8]		; x
	movzx	eax, word [r8 + 2]	; y

	mov	dword [rsp], ecx
	movd	xmm1, eax

	movzx	eax, word [r8 + 4]
	mov	edx, [r8 + 8]
	mov	r11d, [r8 + 12]
	mov	r14, [r8 + 14]
	mov	r13, [r9 + DRAWBUFF.ptr]
	mov	r10d, [r9 + DRAWBUFF.bpl]
	xor	ebx, ebx
	xor	r11, r11
	mov	[rsp + 12], eax


	lea	r8, [font_7px]		; r8 = font_7px (ID gets converted to memory poiner)


.draw_symbol:
	movzx	eax, byte [r14]
	mov	ecx, 3
	add	r14d, 1
	cmp	[r8], ax		; check max supported symbol id
	mov	ebp, [r8 + 4]		; get offset for the SYMBOLS label
	cmovbe	eax, ecx
	movd	[rsp + 4], xmm1

	mov	esi, [r8 + 8 + rax*4]
	movzx	eax, si 		; ax = width,height,starting y, spacers
	shr	esi, 16 		; si = offset withing SYMBOLS section
	movzx	ecx, al
	movzx	r12d, al
	shr	eax, 12 		; starting y coordinate
	and	ecx, 15 		; height
	shr	r12d, 4 		; width
	xorps	xmm0, xmm0
	mov	dword [rsp + 8],  ecx
	jz	.next_symbol

	lea	ecx, [r12 + 1]
	add	rsi, rbp
	add	[rsp + 4], eax
	movd	xmm0, ecx
	add	rsi, r8

	mov	r15d, -64
@@:	lodsq
	add	r15d, 64
.next_pixel:
	bsf	rcx, rax
	jz	@b
	btr	rax, rcx
	xchg	rcx, rax
	xor	edx, edx
	add	eax, r15d
	div	r12d			; return in edx:eax  x:y
	cmp	dword [rsp + 8], eax
	jbe	.next_symbol

	add	eax, [rsp + 4]		; y++
	add	edx, [rsp]		; x++
	mov	ebp, eax
	mov	edi, edx
	imul	ebp, r10d
	imul	edi, 3
	add	rbp, r13
	mov	rax, rcx
	mov	[rbp + rdi], bx 	; draw pixel
	mov	[rbp + rdi + 2], r11b
	jmp	.next_pixel

.next_symbol:
	movd	eax, xmm0
	sub	dword [rsp + 12], 1
	jz	.exit
	add	dword [rsp], eax
	jmp	.draw_symbol



.exit:

	add	rsp, 24
	pop	r15
	ret

