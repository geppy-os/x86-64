
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;//////    System Thread    ////////////////////////////////////////////////////////////////////////
;===================================================================================================

; save vars on user stack, we modify stack, put there data and a return address for the timer handler
; return addr comes from "registers" block
; from timer handler we go executing regular code of the same thread, and it'll call sleep if nothing to do

	align 8
os_loop:
	add	byte [qword 160*24], 1


	;cli
	;mov	 eax, [_y]
	;shl	 eax, 16
	;mov	 ax, [_x]
	;mov	 ecx, [qword reg32.cursor]
	;mov	 [qword reg32.cursor], 84
	;reg	 rax, 80c
	;mov	 [qword reg32.cursor], ecx
	;sti

	call	fragmentRAM


	cmp	dword [lapicT_time], 0xde00'0000
	jb	@f

	bts	qword [k64_flags], 63
	jc	@f

	mov	r8d, 1000*10+10
	lea	r9, [timer1]
	mov	r12, 0x6666666666666666
	mov	r13, 0x7777777777777777
	call	timer_in

	mov	r8d, 1000*999+10
	lea	r9, [timer1]
	mov	r12, 0x6666666666666666
	mov	r13, 0x7777777777777777
	call	timer_in
;
@@:






	;-----------------------------------------------------------------------------------
	cmp	dword [qword lapic + LAPICT_INIT], 0
	; now we get interrupt that triggers thread resume from sleep and we got HLT here
	; not an issue actually
	jnz	@f
	mov	rax, cr8
	hlt
@@:	jmp	os_loop




	; need to copy 24bit into 16,24,32 bit LFB


; all tasks are expected to be mapped in so we need to sanitize all input prior to
; executing ring0 code on user input
; Tasks occupy sequential 512GB memory, not shared




;===================================================================================================
; input: [rsp]	    = # of bytes on stack. To be added to RSP register for "ret" to execute properly
;	 [rsp + 8]  = user data1
;	 [rsp + 16] = user data2
;	 [rsp + 24] = reserved (time in ?microseconds at which this timer event was scheduled)
;---------------------------------------------------------------------------------------------------
; timer fires out-of-order and can interrupt ANY code except for another timer
; timer handler exits to the same thread, if thread was sleeping then go back to sleep

	align 8
timer1:
	add	dword [qword 160*24+4], 1

	mov	r15, 0x400000
	mov	eax, [lapicT_time]
	reg	rax, 80b

	mov	rax, [rsp + 8]
	reg	rax, 1006
	mov	rax, [rsp + 16]
	reg	rax, 1006
	movzx	eax, word [lapicT_currTID]
	reg	rax, 40a


	rdtsc
	mov	esi, [lapicT_time]
	movzx	edi, ah
	imul	rsi, rdi
	mov	ecx, eax
	ror	rsi, cl
	xor	rax, rsi
	xor	rcx, rsi
	xor	rdx, rsi
	xor	rdi, rsi
	xor	rbx, rsi
	xor	rbp, rsi
	xor	r8, rsi
	xor	r9, rsi
	xor	r10, rsi
	xor	r11, rsi
	xor	r12, rsi
	xor	r13, rsi
	xor	r14, rsi


	add	rsp, [rsp]
	jmp	timer_exit




	align 8
timer2:
	add	dword [qword 160*24+6], 1

	mov	r15, 0x400000
	mov	eax, [lapicT_time]
	reg	rax, 80b

	mov	rax, [rsp + 8]
	reg	rax, 1005
	mov	rax, [rsp + 16]
	reg	rax, 1005


	rdtsc
	mov	esi, [lapicT_time]
	movzx	edi, ah
	imul	rsi, rdi
	mov	ecx, eax
	ror	rsi, cl
	xor	rax, rsi
	xor	rcx, rsi
	xor	rdx, rsi
	xor	rdi, rsi
	xor	rbx, rsi
	xor	rbp, rsi
	xor	r8, rsi
	xor	r9, rsi
	xor	r10, rsi
	xor	r11, rsi
	xor	r12, rsi
	xor	r13, rsi
	xor	r14, rsi


	add	rsp, [rsp]
	jmp	timer_exit

