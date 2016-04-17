
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
g2d_drawText:
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



;---------------------------------------------------------------------------------------------------
; code bellow doesn't require per pixel coordinate clipping

.no_clipping:


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
	mov	word [rbp + rdi], 0 ;bx        ; draw pixel
	mov	byte [rbp + rdi + 2], 0;r11b
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









;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

macro left_for_later{
; drawing code may crash if incorrect font data (directions), unless per pixel clipping involved
; need to render in ring3 and blit bitmaps
; Bitmap font (different type of font, unrelated to "blit bitmaps") shouldn't crash

; Suppose it does crash with #PF (only screen data affected), we need to jump out of PF handler,
; terminate task that supplied invalid input, and switch to another task

	align 8
g2d_drawText:
	sub	rsp, 24

	mov	dword [rsp], 40
	mov	dword [rsp + 4], 40



	movzx	ecx, word [r8 + 4]
	mov	ecx, 2
	mov	rax, [r8 + 14]
	mov	edx, [r8 + 8]
	mov	r8b, [r8 + 10]
	mov	[rsp + 12], ecx
	mov	[rsp + 16], rax


	mov	r10d, [r9 + DRAWBUFF.bpl]
	lea	r12, [text_directions]
	mov	r13, [r9 + DRAWBUFF.ptr]


.next_symbol:
	mov	rax, [rsp + 16]
	movzx	esi, byte [rax]
	lea	rbp, [font_7px]
	add	qword [rsp + 16], 1
	movzx	eax, word [rbp + 2 + rsi*2]
	cmp	[rbp], si
	;jnz	 ...

	lea	rbp, [font_7px.SYMBOLS]
	add	rbp, rax


	movzx	ecx, byte [rbp]
	mov	edi, ecx
	and	ecx, 15
	shr	edi, 4
	mov	r11d, edi
;	 shr	 ecx, 4 		 ; cl = number of strokes
	mov	dword [rsp + 8], ecx
	add	rbp, 1

	add	dword [rsp], r11d

.next_curve:
	movzx	edi, byte [rbp] 	; dil = x/y of the current stroke
	movzx	r14d, byte [rbp + 1]	; r14b = # of 3bit chunks in current stroke

	mov	esi, r14d
	lea	esi, [rsi*3]
	add	esi, 7
	shr	esi, 3			; esi = # of bytes before next stroke or new symbol

	mov	rax, [rbp + 2]
	lea	rbp, [rbp + 2 + rsi]

	mov	esi, edi
	and	edi, 15 		; y
	shr	esi, 4			; x
	add	edi, [rsp + 4]
	add	esi, [rsp]
	movq	xmm7, rbp
@@:
	mov	ebp, edi
	mov	ebx, esi
	imul	ebp, r10d
	imul	ebx, 3
	add	ebp, ebx
	mov	[rbp + r13], dx
	mov	[rbp + r13 + 2], r8b

	sub	r14d, 1
	jc	@f

	; next pixel:
	mov	ecx, eax
	shr	rax, 3
	and	ecx, 7
	movsx	ebp, byte [r12 + rcx*2] 	; y
	movsx	ecx, byte [r12 + rcx*2 + 1]	; x
	add	edi, ebp
	add	esi, ecx
	jmp	@b
@@:
	movq	rbp, xmm7		; pointer to next curve
	sub	dword [rsp + 8], 1	; number of curves -= 1
	jz	@f
	jmp	.next_curve
@@:
	add	dword [rsp],1
	sub	dword [rsp + 12], 1
	jz	.exit
	jmp	.next_symbol



.exit:
	add	rsp, 24
	ret


.a:		db 0x7'2	; width=7, number of strokes =2
		db 0x0'4,10	; BYTE1: x=0/y=4,  BYTE2: # of 3bit chunks =10
		db 11'011'010b,1'110'011'0b,101'101'10b,110'101b
		db 0x4'6,9	; x/y, # of 3bit chunks
		db 11'111'111b, 0'101'100'1b, 011'011'11b, 011b

.s:		db 0x6'1, 0x5'4, 17
		db 11'111'000b,1'100'111'1b,011'110'10b,10'011'011b,1'100'101'1b,111'111'11b,000b

}


