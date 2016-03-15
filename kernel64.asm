
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
	call	pci_figureMIMO
	call	pci_getBARs			; disables devices I/O, best done when nothing running

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

	; init RTC and measure LapicTimer speed
	;-------------------------------------------

	mov	r8d, 0x11'f1
	mov	r9, 'PNP0B00' ; find this ID in ACPI, load driver that provides int handler
	call	dev_install


	call	fragmentRAM
@@:	call	fragmentRAM
	jc	k64err				; not enough memory
	cmp	dword [qword memTotal], 0x2000	; need min 128MB (3 function calls is required)
	jb	@b
@@:
	call	update_PF_ram
	cmp	word [PF_pages + 6], 0x800	; min 32MB for #PF, one call gets us max 15.9MB
	jb	@b

	call	refill_pagingRam

	; wait for lapic timer speed to be measured so that we can use timers
	;     We can't put CPU to sleep as lapic timer will be suspended And there will be a slight
	;     delay before timer returns to full speed as CPU is waking up.
	;     A simple HLT instruction on modern CPUs will put CPU to noticebale sleep mode.

@@:
	cmp	byte [rtc_job], 0
	jz	.calc_timer_speed
	call	fragmentRAM

	pushf
	rdtsc  ;
	popf

	jmp	@b

.calc_timer_speed:
	call	lapicT_calcSpeed

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



	;mov	 dword [lapicT_time], 0xffff'ffff - 0x19000


	mov	dword [qword lapic + LAPICT_INIT], 0x202


	mov	r8d, 1000*0x35+10
	lea	r9, [timer1]
	mov	r12, 0x1212'0000'0000'abcd
	mov	r13, 0xcccc'00f0'1000'3232
	call	timer_in


	mov	r8d, 1000*0x39+10
	lea	r9, [timer2]
	call	timer_in





	;mov	 r8d, 1000*0x37+10
	;lea	 r9, [timer_entry]
	;call	 timer_in

	mov	r8d, 1000*0x33+10
	lea	r9, [timer1]
	mov	r12, 0x4444
	mov	r13, 0x5555 shl 48
	;call	 timer_in






	;mov	 r8, PG_USER
	;mov	 r9d, 64
	;call	 thread_create
	;jc	 k64err

	;mov	 [qword  512*1024*1024*1024*2 + 0x200000-8], rax






	mov	eax, [lapicT_ms]
	reg	rax, 81e
	mov	eax, [lapicT_us]
	reg	rax, 81e
	mov	rax, [PF_pages]
	reg	rax, 101e
	mov	eax, [qword memTotal]
	reg	rax, 101e





	movzx	ebp, byte [qword max_pci_bus + rmData]
	reg	rbp, 84f
	shl	ebp, 16
	or	ebp, 0x8000ffff 		; max bus:dev:func
	push	rbp
	reg	rbp, 84f

	mov	esi, 0x80000000
	jmp	.pci_scan_2
.pci_scan:
	or	esi, 0x700
	add	esi, 0x100			; device++
.pci_scan_2:
	xor	bx, bx
	cmp	esi, [rsp]
	jae	.done_pci_scan

reg rsi, 804
	mov	dx, 0xcf8
	mov	eax, esi			; vendor, device
	out	dx, eax
	mov	dx, 0xcfc
	in	eax, dx
	mov	ecx, eax

	lea	eax, [esi + 0xc]		; BIST, Header, 2 more values
	mov	dx, 0xcf8
	out	dx, eax
	mov	dx, 0xcfc
	in	eax, dx

	; BX must be 0 if valid device/vendor
	cmp	cx, -1
	setz	bl				; bx = 1 if invalid device/vendor
	cmp	cx, 1
	adc	bx, 0				; bx >=1 if invalid device/vendor
	jnz	.pci_func

	mov	ebx, eax

	lea	eax, [esi + 0x8]		; classcode, revision
	mov	dx, 0xcf8
	out	dx, eax
	mov	dx, 0xcfc
	in	eax, dx

	reg	rcx, 806
	reg	rax, 806
	reg	rbx, 806

	mov	eax, ebx
.pci_func:
	cmp	eax, -1
	jz	.pci_scan
	bt	eax, 23 			; is this multi function device
	jnc	.pci_scan

@@:
	add	esi, 0x100
	test	esi, 0x700
	jz	.pci_scan_2

reg rsi, 80a

	mov	dx, 0xcf8
	mov	eax, esi
	out	dx, eax
	mov	dx, 0xcfc
	in	eax, dx

	cmp	ax, -1
	jz	@b
	test	ax, ax
	jz	@b

	mov	ecx, eax

	lea	eax, [esi + 0xc]		; BIST, Header, 2 more values
	mov	dx, 0xcf8
	out	dx, eax
	mov	dx, 0xcfc
	in	eax, dx

	mov	ebx, eax

	lea	eax, [esi + 0x8]		; classcode, revision
	mov	dx, 0xcf8
	out	dx, eax
	mov	dx, 0xcfc
	in	eax, dx

	reg	rcx, 806
	reg	rax, 806
	reg	rbx, 806

	jmp	@b

.done_pci_scan:
	add	rsp, 8


; save vars on user stack, we modify stack, put there data and a return address for the timer handler
; return addr comes from "registers" block
; from timer handler we go executing regular code of the same thread, and it'll call sleep if nothing to do

;===================================================================================================
;//////    System Thread    ////////////////////////////////////////////////////////////////////////
;===================================================================================================
	align 8
os_loop:
	add	byte [qword 160*24], 1




	cmp	dword [lapicT_time], 0xde00'0000
	jb	@f

	bts	qword [k64_flags], 63
	jc	@f

	mov	r8d, 1000*999+10
	lea	r9, [timer1]
	call	timer_in

@@:






	;-----------------------------------------------------------------------------------
	test	dword [k64_flags], 1	; could use LAPICT_CURRENT OR LAPICT_INIT(better)
	jnz	@f
	mov	rax, cr8
	hlt
@@:	jmp	os_loop


;===================================================================================================
; input: [rsp]	    = # of bytes on stack. To be added to RSP register for "ret" to execute properly
;	 [rsp + 8]  = user data1
;	 [rsp + 16] = user data2
;	 [rsp + 24] = undefined (time in ?microseconds at which this timer event was scheduled)

	align 8
timer1:
	add	dword [qword 160*24+4], 1

	mov	rax, [rsp + 8]
	reg	rax, 1006
	mov	rax, [rsp + 16]
	reg	rax, 1006

	add	rsp, [rsp]
	ret


	align 8
timer2:
	add	dword [qword 160*24+6], 1

	mov	rax, [rsp + 8]
	reg	rax, 1005
	mov	rax, [rsp + 16]
	reg	rax, 1005

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
