
; Distributed under GPL v1 License
; All Rights Reserved.


;===================================================================================================
; LAPIC Timer is triggered because we need something new to run, not because something expired


; we need to return number lapicT ticks to the caller so that it can schedule next timer
; so that resonable periodic timer can be achieved

	align 8
int_lapicTimer:
	add	byte [qword 0], 1
	push	r15 r13
	mov	r13d, [qword lapic + LAPICT_INIT]
	;mov	 dword [qword lapic + LAPICT_INIT], -1
	push	rax rcx rsi rdi rbp r8 r9 r12 r14
	sub	rsp, 64

	mov	r15, [sp_lapicT_r15]
	mov	eax, [sp_lapicT_flags]
	shl	r15, 16

	push	rax r15
	lea	rbp, [timers_local]
	call	timer_list
	pop	r15 rax

	; check if handler was called due to hadrware interrupt or with an "INT n" instruction
	test	eax, 1 shl 2				; 4
	jz	@f
	or	dword [sp_lapicT_flags], 1 shl 3	; 8
	test	eax, 1 shl 3
	jnz	k64err					; error if "INT n" was executed twice in a row
	jmp	.after_int				; simply exit if no thread switch requested
@@:
;--------------------------------------------------------
	test	eax, 10000b				; flag =1 if we have timer event
	jz	.find_thread				;      =0 if regular thread switch

	; remove old timer entry from the list - we'll switch to this thread

	xor	ecx, ecx
	bt	eax, 0					; 2 different "heads" and counters for timers
	setc	cl
	; TODO: NEED check if thread counter is 0 then switch trhead list

	mov	r8d, [timers_local + TIMERS.head + rcx*8]
	mov	rsi, [timers_local + TIMERS.ptr]
	mov	edi, r8d
	imul	r8d, sizeof.TIMER
	sub	[timers_local + TIMERS.cnt + rcx*8], 1
	jc	k64err
	jnz	@f
	btc	dword [lapicT_flags], 0 		; switch timer list if curent list count =0
@@:
	mov	eax, dword [rsi + r8 + TIMER.next]
	movzx	r9d, ax 				; next	r9   bp (point to 2nd)
	shr	eax, 16 				; prev	rax  cx (points to last)
	mov	[timers_local + TIMERS.head + rcx*8], r9d
	mov	ebp, r9d
	mov	ecx, eax
	imul	r9d, sizeof.TIMER
	imul	eax, sizeof.TIMER

	mov	[rsi + r9 + TIMER.prev], cx
	mov	[rsi + rax + TIMER.next], bp

	mov	r9d, [timers_local + TIMERS.1stFree]
	mov	rcx, [rsi + r8 + TIMER.data2]		; rcx
	mov	[rsi + r8 + TIMER.data2], r9
	mov	[timers_local + TIMERS.1stFree], edi

	mov	rdi, [rsi + r8 + TIMER.data1]		; rdi
	mov	rax, [rsi + r8 + TIMER.returnPtr]	; rax
	mov	esi, dword [rsi + r8 + TIMER.gPID]	; rsi

	; we get threadID and 3 additional data pieces

	jmp	.find_new_thread

;--------------------------------------------------------
.find_thread:
	; we could put priority threads on the list and cycle thru them without removing them
	; only sleep removes threads from the list


.find_new_thread:

	; find next thread to schedule for future
	;-----------------------------------------------

	lea	rbp, [timers_local]
	call	timer_list

	xor	r14, r14
	;not	 r14					 ; r14 = time when next timer thread must run
.find_timer:
	mov	ebp, [lapicT_flags]
	xor	r8, r8
	bt	ebp, 0
	setc	r8b
	mov	r9d, [timers_local + TIMERS.head + r8*8]
	mov	r12, [timers_local + TIMERS.ptr]
	imul	r9d, sizeof.TIMER
	cmp	[timers_local + TIMERS.cnt + r8*8], 0
	jz	.exit ;.find_priority_thread

	mov	r14, [r12 + r9 + TIMER.wakeUpAt]

.find_priority_thread:
	xor	r12, r12				; r12 = time2
	not	r12
	reg	r14, 1006


	; convert time to lapic timer ticks
	mov	r8d, [lapicT_ms]
	mov	r9d, [lapicT_us]
	mov	ebp, r14d				; us
	shr	r14, 32 				; ms
	imul	rbp, r9
	xor	r9, r9
	imul	r14, r8
	not	r9d
	add	rbp, r14
	jc	k64err
	cmp	rbp, r9
	ja	k64err

	mov	[qword lapic + LAPICT_INIT], ebp


.exit:
	btr	dword [sp_lapicT_flags], 3		; always resets bit 3
	jc	.noInt

.after_int:
	add	rsp, 64
	pop	r14 r12 r9 r8 rbp rdi rsi rcx rax r13 r15
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

	align 8
.noInt:
	add	rsp, 64
	pop	r14 r12 r9 r8 rbp rdi rsi rcx rax r13 r15
	iretq


;===================================================================================================

	align 8
lapicT_calcSpeed:
	push	rax rcx rdx rsi rdi rbp

	mov	esi, calcTimerSpeed
	mov	eax, [rsi + 4]
	mov	edi, [rsi + 8]
	mov	ebp, [rsi + 12]
	mov	esi, [rsi + 16]
	neg	eax
	neg	edi
	neg	esi
	neg	ebp
	add	rax, rsi
	add	rdi, rbp
	add	rax, rdi
	shr	rax, 2

	;--- calculate for 1ms ----

	mov	r8, rax
	imul	rax, 1000000

	mov	edi, 1953125
	xor	edx, edx
	div	rdi		; eax = number of lapicT ticks each millisecond for the divider of 2

	xor	edi, edi
	not	edi
	mov	rsi, rdx
	cmp	rax, rdi
	ja	k64err

	shl	rsi, 32
	or	rax, rsi
	mov	[lapicT_ms], rax
	;reg	 rax, 101f

	;--- calculate for 1us ----  (1ms = 1000us)

	mov	esi, 1000000
	mov	rax, r8
	imul	rax, rsi

	mov	esi, 1953125 * 1000
	xor	edx, edx
	div	rsi		; eax = number of lapicT ticks each microsecond for the divider of 2
	mov	rsi, rdx
	test	rax, rax
	jz	k64err

	shl	rsi, 32
	or	rax, rsi
	mov	[lapicT_us], rax
	;reg	 rax, 101f

	pop	rbp rdi rsi rdx rcx rax
	ret

