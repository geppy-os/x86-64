
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
; input:  r8 - pointer to user data
;	      (+0 x, +2 y, +4 width, +6 height, +8 color, +12 byte !=0 if fully transparent, +13 byte=0)
;	  r9 - pointer to destination DRAWBUFF struct
;---------------------------------------------------------------------------------------------------
; all input coordinates are signed 2byte values, width & height must be positive
; DRAWBUFF clipping coordinates are assumed to be signed positive 4byte values, right>=left, bottom>=top
;---------------------------------------------------------------------------------------------------

	align 8
g2d_fillRect:
	sub	rsp, 32

	lea	rax, [rip]
	shr	rax, 39
	shl	rax, 39
	bts	qword [rax + 8192 + functions], FN_G2D_FILLRECT


	movsx	eax, word [r8]			; x1				EAX
	movsx	esi, word [r8 + 4]		; width 			ESI
	mov	ecx, [r9 + DRAWBUFF.clip.left]
	mov	edi, [r9 + DRAWBUFF.clip.right]
	cmp	esi, 0
	jle	.exit
	cmp	byte [r8 + 12], 0
	jnz	.exit

	; will be moved out:
	;cmp	 [r9 + DRAWBUFF.bpp], 3 	 ; need 24bits per pixel
	;jnz	 .exit

	; for the X
	mov	edx, ecx
	sub	ecx, eax			; positive -= pos or neg
	cmp	ecx, 0
	jle	@f
	mov	eax, edx
	sub	esi, ecx
	jbe	.exit
@@:
	movsx	ebp, word [r8 + 2]		; y1				EBP
	movsx	ecx, word [r8 + 6]		; height			ECX
	add	esi, eax			; width + x1 = x2
	cmp	edi, esi			; max allowed x2 - desired x2
	cmovc	esi, edi			; update x2 if needed
	mov	r12d, [r9 + DRAWBUFF.clip.top]
	mov	edi, [r9 + DRAWBUFF.clip.bottom]
	sub	esi, eax			; new x2 -= x1 = new Width
	jbe	.exit

	; for the Y
	mov	edx, r12d			; a copy
	sub	r12d, ebp			; positive -= pos or neg
	cmp	r12d, 0
	jle	@f				; jump if original input y >= min allowed y
	mov	ebp, edx			; new y1 = min allowed y
	sub	ecx, r12d			; new height -= diff betw min allow y & origin input y
	jbe	.exit				; maybe 0 height ?
@@:
	add	ecx, ebp			; height + y1 = y2
	cmp	edi, ecx			; max allowed y2 - desired y2
	cmovc	ecx, edi			; update y2 if needed
	sub	ecx, ebp			; new y2 -= y1 = new Height
	jbe	.exit				; maybe 0 height ?
	;--------------------------------------------------------------------



	mov	r13d, [r9 + DRAWBUFF.bpl]	; r13, rcx, rsi, rdi
	mov	r9, [r9 + DRAWBUFF.ptr]

	mov	r10d, eax
	imul	eax, 3
	imul	ebp, r13d
	add	r9, rax
	add	r9, rbp
	mov	r12, r9
	mov	r14d, esi

	mov	eax, [r8 + 8]
	mov	[rsp], eax
	mov	[rsp + 3], eax
	mov	[rsp + 6], eax
	mov	[rsp + 9], eax
	mov	[rsp + 12], eax
	mov	[rsp + 15], eax
	mov	[rsp + 18], eax
	mov	[rsp + 21], eax

	lea	r8d, [r13 * 2]			; copy of "bytes per line"
	lea	rdi, [r9 + r13] 		; ptr to 2nd line

	mov	rdx, [rsp]			;	   gr-bgr-bgr
	mov	rax, [rsp + 8]			;	   r-bgr-bgr-b
	mov	rbx, [rsp + 16] 		;	   bgr-bgr-gb
						; high byte	     low byte


	; For rects that have 1-5px width, speed increase is minimum
	; in comparasion to 6px width. Additional speed is mainly achieved
	; due to combining instructions that draw 2 horizontal lines per single loop pass.

	cmp	esi, 2
	jb	.1px
	jz	.2px_line
	cmp	esi, 4
	jb	.3px_line
	jz	.4px_line
	cmp	esi, 6
	jb	.5px_line
	jz	.6px_line
	cmp	esi, 8
	jb	.7px_line
	jz	.8px_line
	cmp	esi, 48 			; 48 = 32px main SSE loop, + 16px to align address
	jb	.medium_length

	movdqu	xmm2, [rsp + 8]
	movq	xmm3, rbx
	movq	xmm1, rdx
	movq	xmm0, rax			;  0   rax
	pslldq	xmm0, 8 			; rax	0
	por	xmm0, xmm1			; rax  rdx   xmm0
	pslldq	xmm1, 8 			; rdx	0
	por	xmm1, xmm3			; rdx  rbx   xmm1
	movdqa	xmm3, xmm0
	movdqa	xmm4, xmm1
	movdqa	xmm5, xmm2

	;-----------------------------
.large_length:
	test	r9, 15
	jz	@f
	mov	[r9], dx
	mov	[r9 + 2], al
	sub	esi, 1
	add	r9, 3
	jmp	.large_length
@@:
	sub	esi, 32
.32px:
	movdqa	[r9], xmm0
	movdqa	[r9 + 16], xmm1
	movdqa	[r9 + 32], xmm2
	movdqa	[r9 + 48], xmm3
	movdqa	[r9 + 64], xmm4
	movdqa	[r9 + 80], xmm5
	add	r9, 96
	sub	esi, 32
	jge	.32px

	add	esi, 32
	jz	@f

	shr	esi, 1
	jnc	.leftovers
	mov	[r9], dx
	mov	[r9 + 2], al
	jz	@f
	add	r9, 3
.leftovers:
	mov	[r9], edx
	mov	[r9 + 4], bx
	add	r9, 6
	sub	esi, 1
	jnz	.leftovers
@@:
	add	r12, r13
	mov	esi, r14d
	mov	r9, r12
	sub	ecx, 1
	jz	.exit
	jmp	.large_length

	;-----------------------------
.medium_length:
	mov	ebp, esi
	mov	[r9], rdx
	mov	[r9 + 8], rax
	mov	[r9 + 16], rbx
	and	ebp, 7
	shr	esi, 3
	imul	ebp, 3
	mov	r14d, esi
	add	r9, rbp
@@:
	mov	[r9], rdx
	mov	[r9 + 8], rax
	mov	[r9 + 16], rbx
	add	r9, 24
	sub	esi, 1
	jnz	@b

	add	r12, r13
	mov	esi, r14d
	mov	r9, r12
	sub	ecx, 1
	jz	.exit
	mov	[r9], rdx
	mov	[r9 + 8], rax
	mov	[r9 + 16], rbx
	add	r9, rbp
	jmp	@b


	align 8
.8px_line:
	mov	[r9], rdx
	mov	[r9 + 8], rax
	mov	[r9 + 16], rbx
	add	r9, r13
	sub	ecx, 1
	jnz	.8px_line
	jmp	.exit

	;-----------------------------
	align 8
.7px_line:
	mov	[r9], rdx
	mov	[r9 + 8], rax
	mov	[r9 + 16], ebx
	mov	[r9 + 20], al
	add	r9, r13
	sub	ecx, 1
	jnz	.7px_line
	jmp	.exit

	;-----------------------------
	align 8
.6px_line:
	mov	[r9], rdx
	mov	[r9 + 8], rax
	mov	[r9 + 16], bx
	add	r9, r13
	sub	ecx, 1
	jnz	.6px_line
	jmp	.exit

	;-----------------------------
	align 8
.5px_line:
	mov	rax, [rsp + 7]
	shr	ecx, 1
	jnc	@f
	mov	[r9], rdx
	mov	[r9 + 7], rax
	jz	.exit
	add	r9, r13
	add	rdi, r13
@@:
	mov	[r9], rdx
	mov	[r9 + 7], rax
	mov	[rdi], rdx
	mov	[rdi + 7], rax
	add	r9, r8
	add	rdi, r8
	sub	ecx, 1
	jnz	@b
	jmp	.exit

	;-----------------------------
	align 8
.4px_line:
	shr	ecx, 1
	jnc	@f
	mov	[r9], rdx
	mov	[r9 + 8], eax
	jz	.exit
	add	r9, r13
	add	rdi, r13
@@:
	mov	[r9], rdx
	mov	[r9 + 8], eax
	mov	[rdi], rdx
	mov	[rdi + 8], eax
	add	r9, r8
	add	rdi, r8
	sub	ecx, 1
	jnz	@b
	jmp	.exit

	;-----------------------------
	align 8
.3px_line:
	shr	ecx, 1
	jnc	@f
	mov	[r9], rdx
	mov	[r9 + 8], al
	jz	.exit
	add	r9, r13
	add	rdi, r13
@@:
	mov	[r9], rdx
	mov	[r9 + 8], al
	mov	[rdi], rdx
	mov	[rdi + 8], al
	add	r9, r8
	add	rdi, r8
	sub	ecx, 1
	jnz	@b
	jmp	.exit

	;-----------------------------
	align 8
.2px_line:
	shr	eax, 16
	shr	ecx, 1
	jnc	@f
	mov	[r9], edx
	mov	[r9 + 4], ax
	jz	.exit
	add	r9, r13
	add	rdi, r13
@@:
	mov	[r9], edx
	mov	[r9 + 4], ax
	mov	[rdi], edx
	mov	[rdi + 4], ax
	add	r9, r8
	add	rdi, r8
	sub	ecx, 1
	jnz	@b
	jmp	.exit

	;-----------------------------
	align 8
.1px:
	shr	ecx, 1
	jnc	@f
	mov	[r9], dx
	mov	[r9 + 2], al
	jz	.exit
	add	r9, r13
	add	rdi, r13
@@:
	mov	[r9], dx
	mov	[r9 + 2], al
	mov	[rdi], dx
	mov	[rdi + 2], al
	add	r9, r8
	add	rdi, r8
	sub	ecx, 1
	jnz	@b
	jmp	.exit

	align 8
.exit:
	lea	rax, [rip]
	shr	rax, 39
	shl	rax, 39
	btr	qword [rax + 8192 + functions], FN_G2D_FILLRECT

	add	rsp, 32
	ret

;===================================================================================================
	align 8
.transparent:
	jmp	.exit
