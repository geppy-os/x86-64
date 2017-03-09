
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


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
	mov	[_xPrev], r8w
	mov	[_yPrev], r9w

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








