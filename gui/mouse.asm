
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


; mouse pointer needs to be updated on screen real time (with noThreadSw and not with CLI)
; all GUI events on a timer
; if we got an interrupt (other than timer) we need to exit to system thread, maybe?

; we need a flag if mouse interrupt happened while we are modifiying LFB

; r9 r8 rbp rdi rsi rbx rcx rax    can be modified




;we need a lock for the rectangle that is occupied by mouse id, then we can draw into that rect




	push	rax rcx rdx rsi rdi rbx rbp r8 r9 r10 r11 r12 r13 r14
	mov	rdx, rsp
	mov	rcx, not 15
	sub	rsp, 128
	and	rsp, rcx
	movdqa	[rsp], xmm0
	movdqa	[rsp + 16], xmm1
	movdqa	[rsp + 32], xmm2
	movdqa	[rsp + 48], xmm3
	movdqa	[rsp + 64], xmm4
	movdqa	[rsp + 80], xmm5
	movdqa	[rsp + 96], xmm6
	movdqa	[rsp + 112], xmm7

	mov	rsi, [qword vbeLfb_ptr + rmData]


@@:
	movdqu	xmm0, [rsi]
	movdqu	xmm1, [rsi + 16]
	movdqu	xmm2, [rsi + 32]
	movdqu	xmm3, [rsi + 48]
	movdqu	xmm4, [rsi + 64]
	movdqu	xmm5, [rsi + 80]
	pand	xmm0, [rdi]
	pand	xmm1, [rdi + 16]
	pand	xmm2, [rdi + 32]
	pand	xmm3, [rdi + 48]
	pand	xmm4, [rdi + 64]
	pand	xmm5, [rdi + 80]
	por	xmm0, [rax]
	por	xmm1, [rax + 16]
	por	xmm2, [rax + 32]
	por	xmm3, [rax + 48]
	por	xmm4, [rax + 64]
	por	xmm5, [rax + 80]
	movdqu	[rsi], xmm0
	movdqu	[rsi + 16], xmm1
	movdqu	[rsi + 32], xmm2
	movdqu	[rsi + 48], xmm3
	movdqu	[rsi + 64], xmm4
	movdqu	[rsi + 80], xmm5
	add	r12, r13
	mov	rsi, r12
	sub	ebp, 1
	jnz	@b



.exit:
	movdqa	xmm0, [rsp]
	movdqa	xmm1, [rsp + 16]
	movdqa	xmm2, [rsp + 32]
	movdqa	xmm3, [rsp + 48]
	movdqa	xmm4, [rsp + 64]
	movdqa	xmm5, [rsp + 80]
	movdqa	xmm6, [rsp + 96]
	movdqa	xmm7, [rsp + 112]
	mov	rsp, rdx
	pop	r14 r13 r12 r11 r10 r9 r8 rbp rbx rdi rsi rdx rcx rax





;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
;input:  r8 - pointer to mouse data

	align 8
g2d_drawCursor:


;macro asd{
	movzx	esi, byte [qword vidModes_sel + rmData]
	imul	esi, sizeof.VBE

	movzx	ecx, [vidModes + rmData + esi + VBE.bps]
	movzx	eax, [vidModes + rmData + esi + VBE.height]
	movzx	eax, word [_y]
	imul	rcx, rax
	mov	edi, [qword vbeLfb_ptr + rmData]
	mov	r8, rdi

	movzx	eax, [vidModes + rmData + esi + VBE.bytesPerPx]
	movzx	rsi, word [_x]
	imul	rsi, rax
	add	rcx, rsi
;}


	;mov	 r12d, screen
	;mov	 eax, [r12 + DRAWBUFF.width]


	mov	dword [r8 + rcx], 0x000000
	mov	dword [r8 + rcx+4], 0x00ffff
	mov	dword [r8 + rcx+8], 0x00ffff
	mov	dword [r8 + rcx+12], 0
	mov	dword [r8 + rcx+16], 0
	mov	dword [r8 + rcx+20], 0
	mov	dword [r8 + rcx+12], 0
	mov	dword [r8 + rcx+16], 0
	mov	dword [r8 + rcx+20], 0




	ret



;	 movzx	 ecx, al			 ; flags	   CX
;	 movzx	 esi, ah			 ; x		SI
;	 shr	 eax, 16			 ; y	     AX
;
;===================================================================================================
; input: cx, si, ax, bx

; device driver code discoveres a mouse, and tells kernel it has found a mouse
; kernel gives out id for this mouse
; device driver code (interrupt handler) supplies this id to kernel when it calls "mouse_add_data"
;

	align 8
mouse_add_data:        ; can use  -  ebp edi r8 r9



	mov	ebp, screen
	movzx	r8d, word [_x]
	movzx	r9d, word [_y]

	cmp	[rbp + DRAWBUFF.ptr], 0
	jz	.noGraphics

	mov	edi, [rbp + DRAWBUFF.clip.right]
	xor	ebx, ebx
	add	si, r8w
	cmovl	si, bx
	sub	edi, 1
	cmp	si, di
	cmova	si, di
	mov	[_x], si

	mov	edi, [rbp + DRAWBUFF.clip.bottom]
	add	ax, r9w
	cmovl	ax, bx
	sub	edi, 1
	cmp	ax, di
	cmova	ax, di
	mov	[_y], ax

	cmp	[_x], r8w
	jnz	@f
	cmp	[_y], r9w
	jnz	@f
	jmp	.exit
@@:
	call	g2d_drawCursor
.exit:
	ret

.noGraphics:
	shl	esi, 16
	mov	si, ax
	reg	rsi, 80a
	jmp	.exit








