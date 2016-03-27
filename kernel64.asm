
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	org 0x29'9991'7000
	;org 0x200000
	use64
LMode:
	mov	eax, 0x10
	mov	ds, ax
	mov	ss, ax

	mov	r15, 0x400000
	lea	rsp, [kStack]

	; TSS setup
	;------------------------------
	lea	rbx, [tss_data]
	lea	r8, [interrupt_stack]
	lea	r9, [HPET1_stack]
	lea	rcx, [lapicT_stack]
	lea	rdi, [PF_stack]
	lea	rsi, [GP_stack]
	lea	rbp, [DF_stack]
	mov	[rbx + 4],r8
	mov	[rbx + 12],r8
	mov	[rbx + 20],r8
	mov	[rbx + 36], rcx
	mov	[rbx + 44], rdi
	mov	[rbx + 52], rsi
	mov	[rbx + 60], rbp
	mov	[rbx + 68], r9

	; setup another GDT
	;---------------------------------
	mov	rax, gdt
	mov	rsi, 0x00af'9a00'0000'ffff	; ring0 code
	mov	rcx, 0x00cf'9200'0000'ffff	; ring0 data
	mov	qword [rax], 0
	mov	qword [rax + 8], rsi		; kernel code, ring 0 CS for SYSCALL
	mov	qword [rax + 16], rcx		; kernel data,	      SS for SYSCALL

	mov	rdi, rbx
	mov	ecx, ebx
	shr	rbx, 32 			; dword 2 & 3
	shr	edi, 16
	shl	ecx, 16 			; dword 0
	ror	di, 8
	ror	edi, 8				; dword 1
	or	ecx, 0x67
	or	edi, 0x8900
	mov	[rax + 48], ecx
	mov	[rax + 52], edi
	mov	[rax + 56], rbx

	; switch to this GDT
	;---------------------------------

	mov	rcx, gdtr
	lea	rsi, [@f]
	mov	word  [rcx], 64-1
	mov	qword [rcx+2], rax
	lgdt	[rcx]
	push	8 rsi
	retf
@@:	mov	ecx, 0x10
	mov	ds, cx
	mov	ss, cx
	mov	es, cx

	; setup IDT
	;---------------------------------

	lea	rbp, [int_handlers]
	lea	rdi, [idt]
	lea	rsi, [_idt_exceptions_lmode]
	xor	ebx, ebx
	mov	rax, 0x8e00'0008'0000
.fill_IDT:
	movzx	ecx, word [rsi]
	add	rsi, 2
	test	ecx, ecx
	jz	@f
	add	rcx, rbp
	ror	ecx, 16
	ror	rcx, 16
	or	rcx, rax
	mov	[rdi + rbx], rcx
@@:	add	ebx, 16
	cmp	ebx, _idt_exceptions_lmode.cnt*16
	jb	.fill_IDT

	mov	byte [rdi + 14*16 + 4], 2	; #PF	IST stack
	mov	byte [rdi + 13*16 + 4], 3	; #GP
	mov	byte [rdi +  8*16 + 4], 4	; #DF


	; set PF stack (don't change the order how vars are saved)
	lea	rax, [PF_r15]
	mov	qword [PF_pages], 0xff'ff
	shr	r15, 16
	mov	qword [rax], r15
	shl	r15, 16
	mov	byte [PF_2nd], 0x33
	mov	byte [PF_?], 0


	; set lapicTimer & RTC stack (don't change the order how vars are saved)
	lea	rax, [lapicT_r15]
	shr	r15, 16
	mov	qword [rax], r15
	shl	r15, 16
	mov	byte [rtc_job], 0
	mov	byte [rtc_cpuID], 0


	; load IDT & TSS
	lea	rsi, [idtr]
	mov	word [rsi], 4095
	mov	[rsi+2], rdi
	lidt	[rsi]
	mov	eax, 48
	ltr	ax

;===================================================================================================

	call	acpi_parse_MADT 		; + setup IOAPICs & ISA->IOAPIC redirection

	; get lapic address
	mov	ecx, LAPIC_MSR
	rdmsr
	mov	ecx, edx
	bt	eax, 8
	jnc	k64err
	and	eax, not 4095
	shl	rcx, 32
	or	rax, rcx

	; map lapic
	mov	rcx, 0xffff'fff0'0000'0000
	mov	rdi, lapic shr 12
	or	rax, 10011b
	or	rcx, rdi
	shl	rdi, 12
	mov	[rcx*8], rax
	invlpg	[rdi]

	mov	r8d, 0x4f
	lea	r9, [int_lapicSpurious]
	call	idt_setIrq

	mov	r8d, 0x120
	lea	r9, [int_lapicTimer]
	call	idt_setIrq

	mov	eax, [qword lapic + LAPIC_SVR]
	and	eax, not 0xff
	or	eax, 0x14f			; lapic enable + idt entry for spurious interrupt
	mov	[qword lapic + LAPIC_SVR], eax
	mov	dword [qword lapic + LAPIC_DFR], 0xf000'0000	; flat model
	mov	dword [qword lapic + LAPICT_DIV], 0		; divide by 2, once and forever
	mov	dword [qword lapic + LAPICT], 0x0'0020

	xor	eax, eax
	mov	cr8, rax
	sti

	mov	r8d, 0x0a2
	lea	r9, [ps2_mouse_handler]
	mov	r12, 0x00'02	      ;timer may have been remapped
	;call	 int_install

	; init RTC and measure LapicTimer speed
	;-------------------------------------------

	mov	r8d, 0x11'f1
	mov	r9, 'PNP0B00' ; find this ID in ACPI, load driver that provides int handler
	call	dev_install


; Wait for LAPIC Timer speed to be measured so that we can use timers
;===================================================================================================
;     We can't put CPU to sleep as lapic timer will be suspended And there will be a slight
;     delay before timer returns to full speed as CPU is waking up.
;     A simple HLT instruction on modern CPUs will put CPU to noticebale sleep mode.


	call	tsc_calibration
	call	pci_figureMMIO
	call	tsc_calibration
	; if user not moving mouse then use TSC - next best thing low bits of a fast timer


@@:	; need some minimum memory fragmented
	call	fragmentRAM
	jc	k64err				; not enough memory
	cmp	dword [qword memTotal], 0x2000	; need min 128MB (min 3 function calls is required)
	jb	@b


@@:	; need to supply some minimum memory for #PF handler
	call	update_PF_ram
	cmp	word [PF_pages + 6], 0x800	; min 32MB for #PF, one call gets us max 15.9MB
	jb	@b


	; and we need some min mem to use for paging structures
	call	refill_pagingRam
	call	tsc_calibration


	; and now we are waiting for lapic timer speed to be measured
@@:	cmp	byte [rtc_job], 0
	jz	.calc_timer_speed
	call	fragmentRAM
	jmp	@b

;===================================================================================================
.calc_timer_speed:
	call	lapicT_calcSpeed
	call	pci_getBARs			; skips Bridges since we are using RTC
	call	tsc_calibration



	; bit set - thread id available
	xor	eax, eax
	mov	rcx, gThreadIDs
	not	rax
	mov	[rcx + 8 ], rax
	mov	[rcx + 16], rax
	mov	[rcx + 24], rax
	shl	rax, 2
	mov	[rcx], rax


	; this simply sets some vars, we are in a system thread already
	call	thread_create_system



	bts	qword [k64_flags], 0
	mov	qword [lapicT_time], 0


	mov	dword [qword lapic + LAPICT_INIT], 0x202

	mov	r8d, 1000*0x35+10
	lea	r9, [timer1]
	mov	r12, 0x1212'0000'0000'abcd
	mov	r13, 0xcccc'00f0'1000'3232
	call	timer_in


	mov	r8d, 1000*0x39+10
	lea	r9, [timer2]
	mov	r12, 0x3333333333333333
	mov	r13, 0x4444444444444444
	call	timer_in



	call	ps2_init



	mov	rax, [lapicT_ms]
	reg	rax, 101e
	mov	rax, [lapicT_us]
	reg	rax, 101e
	mov	rax, [PF_pages]
	reg	rax, 101e
	mov	eax, [qword memTotal]
	reg	rax, 101e



	mov	r8, -1
	call	g2d_init_screen
	jc	.55

	call	mouse_draw

	; need screen rotaion
	; need 16,24,32 bits support, to copy to lfb


	movzx	esi, byte [qword vidModes_sel + rmData]
	imul	esi, sizeof.VBE
	movzx	ecx, [vidModes + rmData + esi + VBE.bps]
	movzx	eax, [vidModes + rmData + esi + VBE.bytesPerPx]


	mov	r8d, [qword vbeLfb_ptr + rmData]
	mov	r9, 768
@@:	mov	dword [r8], 0xff0000
	add	r8, 4
	add	r8, rcx
	sub	r9, 1
	jnz	@b

	mov	r8d, [qword vbeLfb_ptr + rmData]
	mov	r9, 1024
.3:	mov	dword [r8], 0xff00
	add	r8, 4
	test	r8, 7
	jnz	@f
	add	r8, rcx
@@:
	sub	r9, 1
	jnz	.3



	sub	rsp, 16
	mov	r8, rsp
	mov	word [r8], 0x21 		; x1
	mov	word [r8 + 2], 2
	mov	word [r8 + 4], 48	     ; width
	mov	word [r8 + 6], 15
	mov	dword [r8 + 8], 0xffb000
	mov	word [r8 + 12], 0
	mov	r9, screen
	;mov	 [r9 + DRAWBUFF.clip.left], 0
	;mov	 [r9 + DRAWBUFF.clip.top], 0
	;mov	 [r9 + DRAWBUFF.clip.right], 1024
	;mov	 [r9 + DRAWBUFF.clip.bottom], 768

	call	g2d_fillRect
	add	rsp, 16



.55:






	;mov	 eax, 5
	;sub	 eax, 3
	;reg	 rax, 804
	;jc	 k64err


;===================================================================================================
;//////    System Thread    ////////////////////////////////////////////////////////////////////////
;===================================================================================================

; save vars on user stack, we modify stack, put there data and a return address for the timer handler
; return addr comes from "registers" block
; from timer handler we go executing regular code of the same thread, and it'll call sleep if nothing to do

	align 8
os_loop:
	add	byte [qword 160*24], 1


	cli
	mov	eax, [_y]
	shl	eax, 16
	mov	ax, [_x]
	mov	ecx, [qword reg32.cursor]
	mov	[qword reg32.cursor], 84
	reg	rax, 80c
	mov	[qword reg32.cursor], ecx
	sti



	cmp	dword [lapicT_time], 0xde00'0000
	jb	@f

	bts	qword [k64_flags], 63
	jc	@f

	mov	r8d, 1000*999+10
	lea	r9, [timer1]
	mov	r12, 0x6666666666666666
	mov	r13, 0x7777777777777777
	call	timer_in

@@:






	;-----------------------------------------------------------------------------------
	cmp	dword [qword lapic + LAPICT_INIT], 0
	; now we get interrupt that triggers thread resume from sleep and we got HLT here
	; not an issue actually
	jnz	@f
	mov	rax, cr8
	hlt
@@:	jmp	os_loop


;===================================================================================================
; input: [rsp]	    = # of bytes on stack. To be added to RSP register for "ret" to execute properly
;	 [rsp + 8]  = user data1
;	 [rsp + 16] = user data2
;	 [rsp + 24] = undefined (time in ?microseconds at which this timer event was scheduled)
;---------------------------------------------------------------------------------------------------
; timer handler need to save/restore all register used


	align 8
timer1:
.sz=16
	pushf
	push	rax
	add	dword [qword 160*24+4], 1

	mov	rax, [rsp + 8+.sz]
	reg	rax, 1006
	mov	rax, [rsp + 16+.sz]
	reg	rax, 1006

	pop	rax
	popf
	add	rsp, [rsp]
	ret


	align 8
timer2:
.sz=16
	pushf
	push	rax
	add	dword [qword 160*24+6], 1

	mov	rax, [rsp + 8+.sz]
	reg	rax, 1005
	mov	rax, [rsp + 16+.sz]
	reg	rax, 1005

	pop	rax
	popf
	add	rsp, [rsp]
	ret



;===================================================================================================
;//////      Errors	////////////////////////////////////////////////////////////////////////////
;===================================================================================================

k64err:
	mov	rax, 'L O N G '
	mov	[qword 900], rax
	jmp	$

.allocLinAddr:
	mov	qword [kernelPanic], 1
	jmp	.kernelPanic

.timerIn_manyLapTicks:
.timerIn_timerCntNot0:
.timerIn_timerCntNot0_1:
.timerIn_timerCntNot0_2:
.lapT_doubleINT:
.lapT_manyTicks:
.lapT_noThreads:
.lapT_timerCntNot0:
.lapicT_wakeUpAt_smaller:

.kernelPanic:
	mov	rax, 'X 6 4 P '
	mov	[qword 120], rax
	mov	rax, 'A N I C '
	mov	[qword 128], rax
	jmp	$


;============================================================================ for debugging ========
reg64:
	pushfq
	push	rdx rbx rax rdi

	mov	ebx, [rsp + 56]
	mov	edx, 16
	mov	ah, bl
	shr	ebx, 8
	cmp	ebx, edx
	cmova	ebx, edx
	lea	edi, [rbx*2 + 2]
	xadd	[qword reg32.cursor], edi
	mov	rdx, [rsp + 48]
	lea	edi, [edi + ebx*2 - 2]
	std
.loop:
	mov	al, dl
	and	al, 15
	cmp	al, 10
	jb	@f
	add	al, 7
@@:	add	al, 48
	stosw
	ror	rdx, 4
	dec	ebx
	jnz	.loop

	pop	rdi rax rbx rdx
	popfq
	ret 16

	align 4
