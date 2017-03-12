
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;     mouse_add_data	 ///////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input:  cx, si, ax, bx
; return:
;---------------------------------------------------------------------------------------------------
; This function is called from an interrupt.
; "mouse_add_data" can exit interrupt handler to do cursor redraw and do GUI events
; There are strict rules that ring0 interrupt handler must follow!
;---------------------------------------------------------------------------------------------------
;
; 1)interrupt calls mouse_add_data (if alot of data then function is called repeatedly within single int)
;     if there are multiple redraw situations then kernel needs to pile up these packets somewhere
;     or maybe use last packet to draw and every single packet to do GUI events
;     Currently, we will skip all but last packet so that kernel doesn't need to care about storage.
;
; 2) kernel needs to call a function (outside interrupt) to process outstanding mouse data
;							 if there is no interrupt for a long time
;				   or not
;
;--------------------------------------------------------------------------------------------------

	align 8
mouse_add_data:
	push	r15 rdx rbp

	lea	rdi, [rip]
	shr	rdi, 39
	shl	rdi, 39
	bts	qword [rdi + 8192 + functions], FN_MOUSE_ADD_DATA

	mov	r15, 0x400000

	mov	ebp, screen
	cmp	[rbp + DRAWBUFF.ptr], 0
	jz	.exit					; .noGraphics

	mov	edi, [rbp + DRAWBUFF.clip.right]	; max 32767
	mov	ebx, [rbp + DRAWBUFF.clip.left]
	add	si, [_x]
	cmovl	si, bx
	sub	edi, 1
	cmp	si, di
	cmova	si, di
	mov	[_x], si

	mov	edi, [rbp + DRAWBUFF.clip.bottom]
	mov	ebx, [rbp + DRAWBUFF.clip.top]
	add	ax, [_y]
	cmovl	ax, bx
	sub	edi, 1
	cmp	ax, di
	cmova	ax, di
	mov	[_y], ax

	mov	eax, [qword lapic + LAPICT_INIT]
	sub	eax, [qword lapic + LAPICT_CURRENT]
	add	rax, [lapicT_time]

	mov	edi, [_x]
	mov	rcx, [redrawTime]
	cmp	rax, [redrawFrame]
	jae	.draw
	btr	word [lapicT_redraw], 0
	jnc	.exit

	bts	word [lock1], 0
	jnc	.draw

.exit:
	lea	rdi, [rip]
	shr	rdi, 39
	shl	rdi, 39
	btr	qword [rdi + 8192 + functions], FN_MOUSE_ADD_DATA
	pop	rbp rdx r15
	ret

.draw2:
	xor	edx, edx
	div	rcx
	imul	rax, rcx
	add	rax, rcx
	mov	[redrawFrame], rax	 ; redrawFrame needs to be updated sooner

	mov	eax, [_x2]
	mov	[_xPrev], eax
	mov	[_x2], edi

	call	g2d_drawCursor
	btr	word [lock1], 0
	jmp	.exit

;===================================================================================================
; Code bellow executes with lapic timer disabled & ints enabled. Only another interrupt can disturb
; it but no thread switches. Another mouse irq can come but there is an entrance lock here - in which
; case mouse irq or kernel needs to pile up non-processed packets (they are currently ignored).
;
; 1) we could disable lapic timer (LAPICT_INIT = 0) for the duraion of the code
;    then we restore old value - we may loose some time
;
; 2) we could disable lapic timer irq (like done bellow) for the duraion of the code
;     then we may loose some time
;
; 3) if we mask timer and set LAPICT_INIT to -1 we can account for missed time
;      but if we account for missed time then we have to mess with TIMER entries
;						     (issue is mainly when "lapicT_time" overflows)
;
; 4) exiting an interrupt is somewhat expensive, tons of code
;
;---------------------------------------------------------------------------------------------------
; Need to save original IRQ return frame (stuff popped by IRETQ) - only once. Dont really need
; separate 4KB but a little space somewhere...
;      (maybe use FN_MOUSE_ADD_DATA as index for storage, per function)

.draw:
	xor	edx, edx
	div	rcx
	imul	rax, rcx
	add	rax, rcx
	mov	[redrawFrame], rax	 ; redrawFrame needs to be updated sooner

	mov	eax, [_x2]
	mov	[_xPrev], eax
	mov	[_x2], edi

	; this mem chunk is part of "devInfo" array, ouch, ouch
	;   (acpi_apic.asm, acpi_parse_MADT, alloc_linAddr, 0x24'00000)
	mov	rsi, 0x2600000-128

	mov	rax, [rsp]		; rbp
	mov	rcx, [rsp + 8]		; rdx
	mov	rdx, [rsp + 16] 	; r15
	mov	rbx, [rsp + 32] 	; rdi
	mov	rdi, [rsp + 40] 	; rsi
	mov	[rsi], rax			; rbp
	mov	[rsi + 8], rcx			; rdx
	mov	[rsi + 16], rdx 		; r15
	mov	[rsi + 24], rbx 		; rdi
	mov	[rsi + 32], rdi 		; rsi

	mov	rax, [rsp + 48] 	; rbx
	mov	rcx, [rsp + 56] 	; rcx
	mov	rdx, [rsp + 64] 	; rax
	mov	[rsi + 40], rax 		; rbx
	mov	[rsi + 48], rcx 		; rcx
	mov	[rsi + 56], rdx 		; rax

	; IRET frame
	mov	rax, [rsp + 72]
	mov	rcx, [rsp + 80]
	mov	rdx, [rsp + 88]
	mov	rbx, [rsp + 96]
	mov	rdi, [rsp + 104]
	mov	[rsi + 64], rax
	mov	[rsi + 72], rcx
	mov	[rsi + 80], rdx
	mov	[rsi + 88], rbx
	mov	[rsi + 96], rdi

	mov	rsp, rsi

	mov	esi, 2
	mov	cr8, rsi			; disable lapic timer irq
	mov	rsi, cr0			;	 (irq will remain pending when happens)
	mov	dword [qword lapic + LAPIC_EOI], 0
	mov	rsi, cr0
	sti					; enable all other irqs
	mov	rsi, cr0




	push	r15
	call	g2d_drawCursor
	pop	r15




	; restore original enviroment of the interrupt that called us
	; and return back to old thread
	mov	rax, cr0
	cli
	mov	rax, cr0
	xor	eax, eax
	mov	cr8, rax
	btr	word [lock1], 0

	lea	rdi, [rip]
	shr	rdi, 39
	shl	rdi, 39
	btr	qword [rdi + 8192 + functions], FN_MOUSE_ADD_DATA

	pop	rbp rdx r15
	pop	rdi rsi rbx rcx rax
	iretq

