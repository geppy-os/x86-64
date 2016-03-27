
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


; mouse pointer needs to be updated on screen real time (with noThreadSw and not with CLI)
; all GUI events on a timer
; if we got an interrupt (other than timer) we need to exit to system thread, maybe?

; we need a flag if mouse interrupt happened while we are modifiying LFB

; r9 r8 rbp rdi rsi rbx rcx rax    can be modified




;	 movzx	 ecx, al			 ; flags	   CX
;	 movzx	 esi, ah			 ; x		SI
;	 shr	 eax, 16			 ; y	     AX
;
;===================================================================================================
; input: cx, si, ax, bx

	align 8
mouse_add_data:        ; can use  -  ebp edi r8 r9


	;----------------------------------------
	mov	ebp, screen
	movzx	r8d, word [_x]
	movzx	r9d, word [_y]

	cmp	[rbp + DRAWBUFF.ptr], 0
	jz	.exit;.noGraphics

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
	call	mouse_draw
.exit:
	ret

.noGraphics:
	shl	esi, 16
	mov	si, ax
	reg	rsi, 80a
	jmp	.exit

;we need a lock for the rectangle that is occupied by mouse id, then we can draw into that rect

;===================================================================================================

	align 8
mouse_draw:


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

	;reg	 rax, 80a

	;add	 edi, ecx

	mov	dword [r8 + rcx], 0x000000
	mov	dword [r8 + rcx+4], 0x00ffff
	mov	dword [r8 + rcx+8], 0x00ffff
	mov	dword [r8 + rcx+12], 0
	mov	dword [r8 + rcx+16], 0
	mov	dword [r8 + rcx+20], 0
	mov	dword [r8 + rcx+12], 0
	mov	dword [r8 + rcx+16], 0
	mov	dword [r8 + rcx+20], 0

.exit:
	ret