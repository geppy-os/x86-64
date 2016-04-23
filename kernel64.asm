
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	org 0x200000				; real linear addr where kernel is copied
LMode2:
	org 0x29'9991'7000			; to catch errors during compilation, 4KB aligned
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

	mov	eax, LMode2 + ((_lmode_ends+32-LMode) and 0xffffe0)
	mov	dword [qword kernelEnd_addr], eax

;===================================================================================================

@@:	; need some minimum memory fragmented
	call	fragmentRAM
	jc	k64err				; not enough memory
	cmp	dword [qword memTotal], 0x2000	; need min 128MB (min 3 function calls is required)
	jb	@b

@@:	; need to supply some minimum memory for #PF handler
	call	update_PF_ram
	cmp	word [PF_pages + 6], 0x1800	; min 96MB for #PF, one call gets us max 15.9MB
	jb	@b

	; and we need some min mem to use for paging structures
	call	refill_pagingRam

;===================================================================================================
; can use memory allocations now, but no timers just yet
;===================================================================================================

	mov	r8, -1
	call	g2d_init_screen 		; it will alloc one large screen buffer

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

	mov	r8d, 0x120			; IST 1, vector 0x20
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
	mov	r8d, 0
	mov	r9, 'PNP' + ('0B00' shl 32)
	call	dev_install
	jc	k64err

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
	;call	 refill_pagingRam
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


	;mov	 r8d, 625*100		 ; 62.5ms
	;lea	 r9, [screen_update]
	;call	 timer_in



	mov	r8d, 1000*0x25+10
	lea	r9, [timer1]
	mov	r12, 0x1212'0000'0000'abcd
	mov	r13, 0xcccc'00f0'1000'3232
	call	timer_in


	mov	r8d, 1000*0x30+10
	lea	r9, [timer1]
	mov	r12, 0x3333333333333333
	mov	r13, 0x4444444444444444
	call	timer_in


	mov	r8d, 1000*500+0x6
	lea	r9, [timer1]
	mov	r12, 0x11111
	mov	r13, 0x22222
	call	timer_in


	mov	r8d, 0x35*1000
	call	sleep


	mov	r8d, 1000*800+0x6
	lea	r9, [timer2]
	mov	r12, -1+0x11111
	mov	r13, -1+0x22222
	call	timer_in


	mov	r8d, 1000*999+0x6
	lea	r9, [timer2]
	mov	r12, -1 xor 0x11111
	mov	r13, -1 xor 0x22222
	call	timer_in


	mov	r8d, 0
	mov	r9, 'PNP' + ('C500' shl 32)
	call	dev_install
	jc	k64err






	mov	rax, [lapicT_ms]
	reg	rax, 101e
	mov	rax, [lapicT_us]
	reg	rax, 101e
	mov	rax, [PF_pages]
	reg	rax, 101e
	mov	eax, [qword memTotal]
	reg	rax, 101e


	cmp	dword [qword vbeLfb_ptr + rmData], 0
	jz	.55

	;call	 mouse_draw

	; need screen rotation
	; need 16,24,32 bits support, to copy to lfb


	movzx	esi, byte [qword vidModes_sel + rmData]
	imul	esi, sizeof.VBE
	movzx	ecx, [vidModes + rmData + esi + VBE.bps]
	movzx	eax, [vidModes + rmData + esi + VBE.bytesPerPx]


	mov	r8d, [qword vbeLfb_ptr + rmData]
	mov	r9, 768
@@:	;mov	 dword [r8], 0xff0000
	add	r8, 4
	add	r8, rcx
	sub	r9, 1
	jnz	@b

	mov	r8d, [qword vbeLfb_ptr + rmData]
	mov	r9, 1024
.3:	;mov	 dword [r8], 0xff00
	add	r8, 4
	test	r8, 7
	jnz	@f
	add	r8, rcx
@@:
	sub	r9, 1
	jnz	.3




	sub	rsp, 16
	mov	r9, vidBuff
	mov	r8, rsp
	mov	eax, [r9 + DRAWBUFF.width]
	mov	ecx, [r9 + DRAWBUFF.height]
	mov	dword [r8], 0
	mov	word  [r8 + 4], ax
	mov	word  [r8 + 6], cx
	mov	dword [r8 + 8], 0xffffff
	mov	word  [r8 + 12], 0
	call	g2d_fillRect
	add	rsp, 16



	sub	rsp, 16
	mov	r8, rsp
	mov	word [r8], 0x21 		; x1
	mov	word [r8 + 2], 2
	mov	word [r8 + 4], 700
	mov	word [r8 + 6], 33
	mov	dword [r8 + 8], 0xffb000
	mov	word [r8 + 12], 0
	mov	r9, vidBuff
	call	g2d_fillRect
	add	rsp, 16


	sub	rsp, 16
	mov	r8, rsp
	mov	word [r8], 40
	mov	word [r8 + 2], 40
	mov	word [r8 + 4], 7	    ; width
	mov	word [r8 + 6], 10
	mov	dword [r8 + 8], 0xffc0ff
	mov	word [r8 + 12], 0
	mov	r9, vidBuff
	call	g2d_fillRect
	add	rsp, 16


	sub	rsp, 32
	mov	r8, rsp
	lea	rax, [text1]
	mov	word  [r8], 10
	mov	word  [r8 + 2], 40
	mov	word  [r8 + 4], text1Len
	mov	word  [r8 + 6], 0 ;font id
	mov	dword [r8 + 8], 0xff ;color
	mov	word  [r8 + 12], 0
	mov	qword [r8 + 14], rax ;text ptr
	mov	r9, vidBuff
	call	txtOut_noClip
	add	rsp, 32


	sub	rsp, 128
	mov	r8, rsp
	mov	word [r8], 5
	mov	word [r8 + 2], 5
	mov	word [r8 + 4], 20	     ; width
	mov	word [r8 + 6], 10
	mov	dword [r8 + 8], 0x00c0ff
	mov	word [r8 + 12], 0
	mov	r9, vidBuff
	call	g2d_fillRect
	add	rsp, 128







	; TODO: need to fix PS2 polarity/trigger
	;	remove junk code


	call	g2d_flush




.55:

	jmp	os_loop 			; jump to "sys_thread.asm"


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
reboot:
	cli
	lea	rsp, [interrupt_stack]
	pushq	0
	lidt	[rsp]
	int	0x44


