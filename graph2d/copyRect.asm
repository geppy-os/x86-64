
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input:  r8 - pointer to user data
;	      (+0 x, +2 y, +4 width, +6 height, +8 color, +12 byte !=0 if fully transparent, +13 byte=0)
;	  r9 - pointer to destination DRABUFF struct
;---------------------------------------------------------------------------------------------------
; all input coordinates are signed 2byte values, width & height must be positive
; DRAWBUFF clipping coordinates are assumed to be signed positive 4byte values, right>=left, bottom>=top
;---------------------------------------------------------------------------------------------------

	align 8
g2d_copyRect_3b_src:
	sub	rsp, 32



.exit:
	add	rsp, 32
	ret

;===================================================================================================
	align 8
.transparent:
	jmp	.exit


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

	align 8
g2d_copyRect_4b_src:
	sub	rsp, 32



.exit:
	add	rsp, 32
	ret



;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; screen double buffers (regular RAM) are always 24bit per pixel, with a multiple of 4pixels per line

	align 8
g2d_copyToScreen:
	mov	r8, vidBuff_changes
	mov	r9, vidBuff
	mov	r12, screen

	mov	eax, [r8 + RECT.left]		; eax = max x0
	mov	edi, [r8 + RECT.top]		; edi = max y0
	mov	ebx, [r9 + DRAWBUFF.clip.left]
	mov	ebp, [r9 + DRAWBUFF.clip.top]
	cmp	eax, ebx
	cmovb	eax, ebx
	cmp	edi, ebp
	cmovb	edi, ebp
	mov	ecx, [r8 + RECT.right]		 ; ecx = min x1
	mov	esi, [r8 + RECT.bottom] 	 ; esi = min y1
	mov	ebx, [r9 + DRAWBUFF.clip.right]
	mov	ebp, [r9 + DRAWBUFF.clip.bottom]
	cmp	ecx, ebx
	cmova	ecx, ebx
	cmp	esi, ebp
	cmova	esi, ebp

	; initial clipping done, result is the rectangle that we are allowed to copy
	;		   from "vidBuff" (which is double buffer) to "screen" (which is VBE LFB)

	sub	ecx, eax			; ecx = width
	jbe	.exit
	sub	esi, edi			; esi = height
	jbe	.exit
	cmp	[r12 + DRAWBUFF.bpp], 4 	; do we copy to 32bit LFB?
	jz	.to_32bpp
;---------------------------------------------------------------------------------------------------


	mov	ebx, eax
	mov	ebp, edi
	mov	r13d, [r12 + DRAWBUFF.bpl]	; r14 r13 r12
	mov	r8d, [r9 + DRAWBUFF.bpl]	; r8 r9 rdi
	imul	ebx, 3
	imul	eax, 3
	imul	ebp, r13d
	imul	edi, r8d
	add	ebp, ebx
	add	edi, eax
	add	rbp, [r12 + DRAWBUFF.ptr]
	add	rdi, [r9 + DRAWBUFF.ptr]
	mov	r12, rbp
	mov	r9, rdi


	mov	ebx, ecx
@@:
	mov	r11w, [rdi]
	mov	dl, [rdi + 2]
	mov	[rbp], r11w
	mov	[rbp + 2], dl
	add	rdi, 3
	add	rbp, 3
	sub	ecx, 1
	jnz	@b

	add	r12, r13
	add	r9, r8
	mov	ecx, ebx
	mov	rbp, r12
	mov	rdi, r9
	sub	esi, 1
	jnz	@b
	jmp	.exit

;---------------------------------------------------------------------------------------------------
.to_32bpp:

	mov	ebx, eax
	mov	ebp, edi
	mov	r13d, [r12 + DRAWBUFF.bpl]	; r14 r13 r12
	mov	r8d, [r9 + DRAWBUFF.bpl]	; r8 r9 rdi
	imul	ebx, 4
	imul	eax, 3
	imul	ebp, r13d
	imul	edi, r8d
	add	ebp, ebx
	add	edi, eax
	add	rbp, [r12 + DRAWBUFF.ptr]
	add	rdi, [r9 + DRAWBUFF.ptr]
	mov	r12, rbp
	mov	r9, rdi


	mov	ebx, ecx
	xor	edx, edx
@@:
	mov	r11d, [rdi]
	and	r11d, 0xffffff
	mov	[rbp], r11d
	add	rdi, 3
	add	rbp, 4
	sub	ecx, 1
	jnz	@b

	add	r12, r13
	add	r9, r8
	mov	ecx, ebx
	mov	rbp, r12
	mov	rdi, r9
	sub	esi, 1
	jnz	@b

.exit:
	ret