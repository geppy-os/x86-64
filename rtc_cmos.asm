
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


init_ps2Mouse:

;===================================================================================================
;  rtc_int   -	normally, this RTC interrupt happens twice a second
;===================================================================================================

    align 16
rtc_int:
	cmp	byte [sp_rtc_job - (104 + 6*8)], 0x7f

	push	rcx r15 r8 rax rsi rdi
	lea	rsp, [rsp - 104]		; we have a "call" here, additional 8bytes of stack

	ja	.lapicT_restart
	jz	.first_init			; 1st interrupt is ignored (after initialization)

	mov	eax, 0xc
	out	0x70, al
	in	al, 0x71

	add	byte [qword 8+txtVidMem], 1
	add	byte [qword time], 1		; <-- need to change this into 31bit value

.exit:
	add	rsp, 104
	pop	rdi rsi rax r8 r15 rcx
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

.first_init:
	mov	eax, 0xc
	out	0x70, al
	in	al, 0x71

	add	byte [sp_rtc_job], 1
	jmp	.exit

;-------------------------------------------------------------
; measure lapic timer ticks 5 times
;-------------------------------------------------------------

	align 16
.lapicT_restart:
	mov	r8d, [qword lapic + LAPICT_CURRENT]
	mov	dword [qword lapic + LAPICT_INIT], -1		; reinit counter
	mov	ecx, 1
	xadd	[sp_rtc_job], cl

	mov	eax, 0xc
	out	0x70, al
	in	al, 0x71

	and	ecx, 127
	jz	.exit
	cmp	ecx, 5				; did we have enough samples ?
	ja	@f				; jump if so

	; save values from [lapic + LAPICT_CURRENT] at [calcTimerSpeed + offset]
	mov	esi, calcTimerSpeed
	lea	rsi, [rsi + rcx*4 - 4]
	mov	[rsi], r8d
	jmp	.exit
@@:
	; stop measurment of lapic timer speed

	mov	dword [qword lapic + LAPICT_INIT], 0		; stop timer
	and	dword [qword lapic + LAPICT], not (1 shl 16)	; and unmask
	mov	byte [sp_rtc_job], 0

	mov	r8d, 1111b			; interrupt happens twice a second
	call	rtc_setRate
	jmp	.exit

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

	align 4
rtc_init:

	mov	r8, [qword devInfo]
	lea	r9, [rtc_int]
	mov	r12d, 0x01'f1
	mov	r8d, [r8 + 8*devInfo_sz]
	call	int_install

	; init the RealTimeClock
	;-------------------------------

	pushf
	cli

	mov	eax, 0x8b
	out	0x70, al	; select B register, and disable NMI(bit7)
	in	al, 0x71	; read from B

	and	eax, 10001111b
	or	eax, 01000000b	; enable periodic only
	mov	ecx, eax

	mov	eax, 0x8b
	out	0x70, al
	mov	eax, ecx
	out	0x71, al	; write to B

	mov	byte [rtc_job], 0x7f
	or	dword [qword lapic + LAPICT], 1 shl 16	; mask timer

	push	rax
	mov	r8d, 0111b	; 512 times a second  (once each 1.953125 ms)
	call	rtc_setRate
	pop	rax

	mov	eax, 0xc
	out	0x70, al
	in	al, 0x71

	popf

	mov	eax, 0xc
	out	0x70, al
	in	al, 0x71

	ret

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8 = 4bit rate
;	 this function must not use stack

	align 4
rtc_setRate:
	and	r8d, 15
	mov	eax, 0x8a
	out	0x70, al
	in	al, 0x71
	and	eax, 0xf0
	or	eax, r8d
	mov	ecx, eax
	mov	eax, 0x8a
	out	0x70, al
	mov	eax, ecx
	out	0x71, al
	ret
