
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
;input:  r8  - pointer to mouse data
;	       (cursor data/image must already properly match the screen)
;	 r9  - pointer to screen DRAWBUFF struct where to draw (24 or 32 bit)
;	 r12 - pointer to doubleBuffer DRAWBUFF struct from where to restore (24bit only)

	align 8
g2d_drawCursor:
	sub	rsp, 64


	; coordinate clipping is missing

	mov	r9, screen
	mov	r12, vidBuff

	mov	dword [rsp], 8			; width 				[RSP]	dword
	mov	dword [rsp + 4], 8		; height				[RSP+4] dword






	mov	r13d, [r12 + DRAWBUFF.bpp]	; bytes per pixel   r13 - edi - esi
	mov	r14d, [r12 + DRAWBUFF.bpl]	; bytes per line    r14 - eax - ecx
	mov	edi, r13d
	mov	eax, r14d
	movzx	esi, word [_xPrev]		;		    esi - ebp
	movzx	ecx, word [_yPrev]		;		    ecx - edx
	mov	ebp, [r9 + DRAWBUFF.bpp]	; bytes per pixel
	mov	edx, [r9 + DRAWBUFF.bpl]	; bytes per line
	imul	edi, esi			; doubleBuff bpp * x
	imul	esi, ebp			; x		 * screen bpp
	imul	eax, ecx			; doubleBuff bpl * y
	imul	ecx, edx			; y		 * screen bpl
	add	rsi, [r9 + DRAWBUFF.ptr]
	add	rdi, [r12 + DRAWBUFF.ptr]
	add	rsi, rcx
	add	rdi, rax

	; result: rsi - points to screen where to start erasing
	;	  rdi - points to doubleBuffer where to start copying from
	;	  r14 - bytes per line for the double buffer

	mov	eax, [rsp + 4]
	mov	rcx, rsi
	mov	rbp, rdi
	mov	ebx, [rsp]
	mov	[rsp + 8], eax
	mov	r10d, 0xffffff



	cmp	[r12 + DRAWBUFF.bpp], 3
	jnz	.exit
	cmp	[r9 + DRAWBUFF.bpp], 4
	jz	.restore32
	cmp	[r9 + DRAWBUFF.bpp], 3
	jz	.restore24
	jmp	.exit

;---------------------------------------------------------------------------------------------------
	align 8
.restore32:
	sub	ebx, 3
	jl	@f
	mov	eax, [rdi]
	mov	r11d, [rdi + 3]
	mov	r13d, [rdi + 6]
	add	rdi, 9
	and	eax, r10d
	and	r11d, r10d
	and	r13d, r10d
	mov	[rsi], eax
	mov	[rsi+4], r11d
	mov	[rsi+8], r13d
	add	rsi, 12
	jmp	.restore32
@@:
	add	ebx, 3
	jz	.switchLine_r32
@@:
	mov	eax, [rdi]
	and	eax, r10d
	mov	[rsi], eax
	add	rdi, 3
	add	rsi, 4
	sub	ebx, 1
	jnz	@b

.switchLine_r32:
	add	rcx, rdx
	mov	ebx, [rsp]
	add	rbp, r14
	mov	rsi, rcx
	mov	rdi, rbp
	sub	dword [rsp + 8], 1
	jnz	.restore32
	jmp	.draw

;---------------------------------------------------------------------------------------------------
	align 8
.restore24:
	sub	ebx, 4
	jl	@f
	mov	rax, [rdi]
	mov	r13d, [rdi + 8]
	add	rdi, 12
	mov	[rsi], rax
	mov	[rsi+8], r13d
	add	rsi, 12
	jmp	.restore24
@@:
	add	ebx, 4
	jz	.switchLine_r24
@@:
	mov	eax, [rdi]
	add	rdi, 3
	mov	[rsi], ax
	shr	eax, 16
	mov	[rsi + 2], al
	add	rsi, 3
	sub	ebx, 1
	jnz	@b

.switchLine_r24:
	add	rcx, rdx
	mov	ebx, [rsp]
	add	rbp, r14
	mov	rsi, rcx
	mov	rdi, rbp
	sub	dword [rsp + 8], 1
	jnz	.restore24

;===================================================================================================
.draw:
	mov	[rsp + 16], r15

	mov	r13d, [r12 + DRAWBUFF.bpp]	; bytes per pixel   r13 - esi - edi
	mov	r14d, [r12 + DRAWBUFF.bpl]	; bytes per line    r14 - eax - ecx		R14
	mov	esi, r13d
	mov	eax, r14d
	movzx	edi, word [_x]			;		    edi - ebp
	movzx	ecx, word [_y]			;		    ecx - edx
	mov	ebp, [r9 + DRAWBUFF.bpp]	; bytes per pixel
	mov	edx, [r9 + DRAWBUFF.bpl]	; bytes per line				EDX
	imul	esi, edi			; doubleBuff bpp * x
	imul	edi, ebp			; x		 * screen bpp
	imul	eax, ecx			; doubleBuff bpl * y
	imul	ecx, edx			; y		 * screen bpl
	add	rdi, [r9 + DRAWBUFF.ptr]
	add	rsi, [r12 + DRAWBUFF.ptr]
	add	rdi, rcx			; points to screen where to draw		RDI
	add	rsi, rax			; points to doubleBuffer where to copy from	RSI

	mov	ebp, 8				; max cursor width
	mov	ebx, [rsp]			;
	mov	ecx, [rsp + 4]
	sub	ebp, ebx
	lea	eax, [rbx * 3]			; drawn cursor width *= bytes_per_pixel(=3)
	shl	ebp, 2
	sub	r14d, eax			; double buffer line width -= cursor width
	mov	[rsp + 8], ecx
	mov	[rsp + 12], ebp

	mov	rbp, rdi
	xor	r13, r13
	cld

	cmp	[r9 + DRAWBUFF.bpp], 3
	lea	r9, [arrow_mask]
	lea	r12, [arrow_clr]
	jz	.draw24
	jmp	.draw32

;---------------------------------------------------------------------------------------------------
	align 16
.draw32:
	sub	ebx, 3
	jl	@f
	mov	eax, [rsi]
	mov	ecx, [rsi + 3]
	mov	r10d, [rsi + 6]
	add	rsi, 9
	and	eax, [r9 + r13]
	and	ecx, [r9 + r13 + 4]
	and	r10d, [r9 + r13 + 8]
	or	eax, [r12 + r13]
	or	ecx, [r12 + r13 + 4]
	or	r10d, [r12 + r13 + 8]
	add	r13d, 12
	mov	[rdi], eax
	mov	[rdi + 4], ecx
	mov	[rdi + 8], r10d
	add	rdi, 12
	jmp	.draw32
@@:
	add	ebx, 3
	jz	.switchLine_d32
@@:
	mov	eax, [rsi]
	add	rsi, 3
	and	eax, [r9 + r13]
	or	eax, [r12 + r13]
	add	r13d, 4
	stosd
	sub	ebx, 1
	jnz	@b

.switchLine_d32:
	add	rbp, rdx
	add	rsi, r14
	mov	ebx, [rsp]
	add	r13d, [rsp + 12]
	mov	rdi, rbp
	sub	dword [rsp + 8], 1
	jnz	.draw32
	jmp	.exit

;---------------------------------------------------------------------------------------------------
	align 16
.draw24:
	sub	ebx, 3
	jl	@f
	mov	eax, [rsi]
	mov	ecx, [rsi + 3]
	mov	r10d, [rsi + 6]
	add	rsi, 9
	and	eax, [r9 + r13]
	and	ecx, [r9 + r13 + 4]
	and	r10d, [r9 + r13 + 8]
	or	eax, [r12 + r13]
	or	ecx, [r12 + r13 + 4]
	or	r10d, [r12 + r13 + 8]
	add	r13d, 12
	mov	[rdi], eax
	mov	[rdi + 3], ecx
	mov	[rdi + 6], r10w
	shr	r10, 16
	mov	[rdi + 8], r10b
	add	rdi, 9
	jmp	.draw24
@@:
	add	ebx, 3
	jz	.switchLine_d24
@@:
	mov	eax, [rsi]
	add	rsi, 3
	and	eax, [r9 + r13]
	or	eax, [r12 + r13]
	add	r13d, 4
	mov	[rdi], ax
	shr	eax, 16
	mov	[rdi + 2], al
	add	rdi, 3
	sub	ebx, 1
	jnz	@b

.switchLine_d24:
	add	rbp, rdx
	add	rsi, r14
	mov	ebx, [rsp]
	add	r13d, [rsp + 12]
	mov	rdi, rbp
	sub	dword [rsp + 8], 1
	jnz	.draw24
	jmp	.exit


.exit:
	add	rsp, 64
	ret