
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;    int_lapicTimer
;===================================================================================================
; !! LAPIC Timer is triggered because we need something new to run, not because something expired !!


	align 8
int_lapicTimer:
	add	byte [qword 0], 1
	push	r15 r13 rax rcx 			; 6 regs in RTC interrupt which shares stack
	sub	rsp, 120
	mov	eax, [sp_lapicT_flags]

	; check if noThreadSw was called prior to entering this handler
	test	eax, 1 shl 2				; 4
	jz	@f					; jump if no block to switch threads
	or	dword [sp_lapicT_flags], 1 shl 3	; 8
	test	eax, 1 shl 3
	jnz	k64err.lapT_doubleINT			; error if "INT n" was executed twice in a row

	; simply exit if no thread switch requested
	add	rsp, 120
	pop	rcx rax r13 r15
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

;---------------------------------------------------------------------------------------------------
	align 8
@@:
	mov	r13d, [qword lapic + LAPICT_INIT]	;			R13
	mov	dword [qword lapic + LAPICT_INIT], -1

	mov	r15,	  [sp_lapicT_r15]
	movzx	ecx, word [sp_lapicT_currTID]
	shl	r15, 16

	; calc address to save old thread registers
	imul	rcx, 0x10000 * 512
	lea	rax, [registers]
	test	rcx, rcx
	cmovz	rcx, rax

	fxsave	[rcx]
	mov	[rcx + 512     ], r14
	mov	[rcx + 512 +  8], rdi
	mov	[rcx + 512 + 16], rsi
	mov	[rcx + 512 + 24], rbx
	mov	[rcx + 512 + 32], rbp
	mov	[rcx + 512 + 40], rdx
	mov	[rcx + 512 + 48], r8
	mov	[rcx + 512 + 56], r9
	mov	[rcx + 512 + 64], r10
	mov	[rcx + 512 + 72], r11
	mov	[rcx + 512 + 80], r12
	mov	rdi, [rsp + 120]			; rcx
	mov	rsi, [rsp + 128]			; rax
	mov	rbx, [rsp + 136]			; r13
	mov	rbp, [rsp + 144]			; r15
	mov	[rcx + 512 +  88], rdi
	mov	[rcx + 512 +  96], rsi
	mov	[rcx + 512 + 104], rbx
	mov	[rcx + 512 + 112], rbp

	mov	rdi, [rsp + 152]			; rip
	mov	rsi, [rsp + 160]			; cs
	mov	rbx, [rsp + 168]			; rflags
	mov	rbp, [rsp + 176]			; rsp
	mov	rdx, [rsp + 184]			; ss
	mov	[rcx + 512 + 120], rdi
	mov	[rcx + 512 + 128], rsi
	mov	[rcx + 512 + 136], rbx
	mov	[rcx + 512 + 144], rbp
	mov	[rcx + 512 + 152], rdx

	mov	r14d, [qword lapic + LAPICT_CURRENT]	;			R14
	xor	ebx, ebx				;			RBX

;===================================================================================================
; if "lapicT_time" doesn't overflow then we keep processing outstanding (if any) list first

; before "lapicT_time" overflow:
; if we adding timers on list #1 then #0 is outstanding which is processed 1st
;			      #0      #1
; After we remove most recent timer thread, we consider potential "lapicT_time" overflow
;
; if lapicT_time overflows then we have only 1 chance to process 1 last outstanding timer entry
;     After we remove outstanding timer entry from the list,
;	 we switch add_list id to the old outstanding list where counter must be 0 by now.
;===================================================================================================


	; process timer list first - all timers have priority over regulary trigerred threads

	add	dword [lapicT_time], r13d		; bring time up to date
	adc	dword [lapicT_flags], 0 		; set bit0 to check counters later

	xor	ecx, ecx
	bt	dword [lapicT_flags], 1 		; get lapicT_time ID (same as add_list ID)
	setc	cl
	xor	ecx, 1					; we'll use opposite(to add_list) list first
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0	; check if counter =0 on outstanding list
	jnz	.process_timer				; process any outstanding timers right away

	xor	ecx, 1
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0	; then check counter on CURRENT list (add_list)
	jz	.process_priority

	; check time on non-outstanding timer list
	mov	ebp, [timers_local + TIMERS.head + rcx*8]
	mov	rsi, [timers_local + TIMERS.ptr]
	mov	eax, [lapicT_time]
	imul	ebp, sizeof.TIMER
	cmp	[rbp + rsi + TIMER.wakeUpAt], rax
	ja	.process_priority			; JUMP if closest timer time doesn't match

	;============================================================
	; delete last timer entry, we'll switch to this thread
	;=============================================================
	; input: rcx,r15,r13,r14, all other regs have undefined value
.process_timer:
	mov	r8d, [timers_local + TIMERS.head + rcx*8]
	mov	rsi, [timers_local + TIMERS.ptr]
	mov	edi, r8d
	imul	r8d, sizeof.TIMER

	; we wont enter another event until previous has finished (r8,rcx,rsi,rdi in use already)
	; (!!! may get unlimited timeslice if new timer entry is constantly encountered)
	;	but we can switch to another priority thread to fix this
	movzx	eax, word [rsi + r8 + TIMER.gTID]
	mov	ebp, [lapicT_ms]
	imul	rax, 0x10000 * 512
	lea	r9, [registers]
	test	rax, rax
	cmovz	rax, r9
	mov	r10d, 4
	imul	r10d, ebp
	xor	r11, r11				; r11 = 0 = priority thread
	test	qword [rax + 8192 + event_mask], 1	; [lapicT_currTID] didn't change
	jnz	.exit

	mov	rbx, rax

	sub	[timers_local + TIMERS.cnt + rcx*8], 1
	jc	k64err

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
	mov	r12, [rsi + r8 + TIMER.data2]		; r12	<<
	mov	[rsi + r8 + TIMER.data2], r9
	mov	[timers_local + TIMERS.1stFree], edi

	; we'll pass this additional data when we switch to this thread:
	movzx	r9d, [rsi + r8 + TIMER.gTID]		; r9
	mov	r13, [rsi + r8 + TIMER.data1]		; r13	<<
	mov	r11, [rsi + r8 + TIMER.returnPtr]	; r11	<<

	mov	[lapicT_currTID], r9w

	;--------------------------------------------------------------------------------------------
	; Timer handler always restores registers of prev event handler when timer handler is exited.
	; These regs will be destroyed if timer handler interrupted by a thread switch.
	; So we make another copy of these registers (at the end of this handler)
	;--------------------------------------------------------------------------------------------

	mov	r10d, 4
	imul	r10d, [lapicT_ms]
	jmp	.exit

;===================================================================================================

	align 8
.process_priority:

	mov	eax, [lapicT_flags]
	mov	esi, [lapicT_priQuene]			; dword (10'00'01'11'00'01'10'00'01'00b shl 8)
	mov	ebp, 1111b
	xor	edx, edx

.search_priorities:
	movzx	ecx, sil				; get index where to look for priority
	mov	edi, esi
	add	ecx, 8					; remove the index
	shr	edi, cl 				; low 2bits is the priority number
	lea	ecx, [rcx - 6]				; switch to next index
	and	edi, 11b
	btr	ebp, edi
	cmp	ecx, 9*2
	movzx	edi, word [lapicT_pri0 + rdi*2] 	; get thread index
	cmova	ecx, edx
	mov	sil, cl 				;					     ESI
	test	ebp, ebp				; exit if all priorities have been looked at
	jz	k64err.lapT_noThreads
	cmp	edi, 0xffff				; exit if non 0xffff thread index is found   EDI
	jz	.search_priorities

	; calculate time-in for closest timer entry/thread (on current add_list)
	;-------------------------------------------------------------------------

	xor	ecx, ecx
	bt	eax , 1 				; using "old" add_list if lapicT_time overflown
	setc	cl
	mov	r8,  [timers_local + TIMERS.ptr]
	mov	r9d, [timers_local + TIMERS.head + rcx*8]
	mov	ebp, -1 				; default timesclice for timer-triggered thread
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0
	jz	.calc_ticks

	imul	r9d, sizeof.TIMER
	mov	rbp, [r8 + r9 + TIMER.wakeUpAt] 	; lapic timer ticks, (currently, 4byte value)

	test	eax, 1
	jnz	.process_timer				; meant to be kernel panic

	sub	ebp, [lapicT_time]			; ebp = timeslice in which to switch thread
	jbe	k64err.lapicT_wakeUpAt_smaller

	; continue with calculating lapic timer ticks for the priority thread
	;-------------------------------------------------------------------------
.calc_ticks:
	mov	[lapicT_currTID], di
	mov	[lapicT_priQuene], esi

	; TODO: set flags

	imul	rdi, sizeof.THREAD
	xor	r11, r11				; =0, RIP taken from thread control block
	movzx	eax, [threads + rdi + THREAD.time2run]	; in microseconds
	xor	edx, edx
	mov	esi, 1000
	mov	r8d, [lapicT_ms]
	div	esi					; to MS:US - milliseconds reduces round errors
	mov	r9d, [lapicT_us]
	imul	rax, r8
	imul	rdx, r9
	mov	esi, 0xffffffff
	add	rax, rdx
	cmp	rax, rsi				; eax = 4byte # of lapic ticks
	jae	k64err.lapT_manyTicks

	; choose minimum value (new thread timeslice) and run the priority thread
	;-------------------------------------------------------------------------
	cmp	ebp, eax
	cmovb	eax, ebp
	mov	r10d, eax

;===================================================================================================
;	check if we need to switch add_list id and therefore verify counter

.exit:							       ; r10 r14
	btr	dword [lapicT_flags], 0
	jnc	@f

	xor	ecx, ecx
	btc	dword [lapicT_flags], 1 		; switch add_list id
	setc	cl					; ecx = old add_list id
	xor	ecx, 1					; old id -> new 	 (setnc cl)

	; add_list counter must be zero if we did switch the lists (no leftover timers present)
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0
	jnz	k64err.lapT_timerCntNot0

;---------------------------------------------------------------------------------------------------
;	calculate from where to restore registers
@@:
	movzx	eax, word [lapicT_currTID]
	imul	rax, 0x10000 * 512
	cmp	rax, 0
	jnz	@f
	mov	r9, [lapicT_kPML4]
	lea	rax, [registers]
	jmp	.switch
@@:
	lea	rdi, [rax + 8192]
	mov	rsi, 0xffff'fff0'0000'0000
	shr	rdi, 12
	or	rdi, rsi
	mov	r9, [rdi*8]

;---------------------------------------------------------------------------------------------------
;	update CR3, process timer events if any, update exit point from this handler
.switch:
	mov	rdi, 0x7fff'ffff'f000			; reload or not CR3 when switching to sys thread ???
	and	r9, rdi
	mov	cr3, r9 				; switch to another thread PML4

	mov	rcx, [rax + 512 + 120]			; rip
	mov	rsi, [rax + 512 + 128]			; cs
	mov	rdi, [rax + 512 + 136]			; rflags
	mov	rbp, [rax + 512 + 144]			; rsp
	mov	rdx, [rax + 512 + 152]			; ss

	test	rbx, rbx				; do we run new thread because of timer entry ?
	jz	@f					; jump if no
	mov	[rbx + 4096], rcx
	mov	[rbx + 4096 + 8], rsi
	mov	[rbx + 4096 + 16], rdi
	mov	[rbx + 4096 + 24], rbp
	mov	[rbx + 4096 + 32], rdx
@@:
	test	r11, r11
	jz	.priority_thread
.sz=32
	sub	rbp, .sz				; could get #PF as soon as we touch user stack
	mov	qword [rbp], .sz			; number of bytes before "iret" frame
	mov	qword [rbp + 8], r13			; user data1
	mov	qword [rbp + 16], r12			; user data2
	mov	qword [rbp + 24], 0			; user data3   ; 1a026 de1f5e2a
	jmp	@f

.priority_thread:
	mov	r11, [rax + 512 + 120]
@@:	mov	[rsp + 152], r11			; rip
	mov	[rsp + 160], rsi			; cs
	mov	[rsp + 168], rdi			; rflags
	mov	[rsp + 176], rbp			; rsp
	mov	[rsp + 184], rdx			; ss

;---------------------------------------------------------------------------------------------------
;	start another timeslice, restore registers

	fxrstor [rax]

	mov	dword [qword lapic + LAPICT_INIT], r10d

	mov	r14, [rax + 512]
	mov	rdi, [rax + 512 + 8]
	mov	rsi, [rax + 512 + 16]
	mov	rdx, [rax + 512 + 40]
	mov	r8,  [rax + 512 + 48]
	mov	r9,  [rax + 512 + 56]
	mov	r10, [rax + 512 + 64]
	mov	r11, [rax + 512 + 72]
	mov	r12, [rax + 512 + 80]
	mov	rcx, [rax + 512 + 88]
	mov	r13, [rax + 512 + 104]
	mov	r15, [rax + 512 + 112]

	; save regs for timer handler to restore
	test	rbx, rbx				; do we run thread because of new timer entry ?
	jz	@f					; jump if no

	fxsave	[rbx + 4096 + 192]

	mov	[rbx + 4096 + 40], r14
	mov	[rbx + 4096 + 48], rdi
	mov	[rbx + 4096 + 56], rsi
	mov	[rbx + 4096 + 80], rdx
	mov	[rbx + 4096 + 88], r8
	mov	[rbx + 4096 + 96], r9
	mov	[rbx + 4096 + 104], r10
	mov	[rbx + 4096 + 112], r11
	mov	[rbx + 4096 + 120], r12
	mov	[rbx + 4096 + 128], rcx
	mov	[rbx + 4096 + 144], r13
	mov	[rbx + 4096 + 152], r15

	mov	rbp, [rax + 512 + 24]		; rbx
	mov	[rbx + 4096 + 64], rbp
	mov	rbp, [rax + 512 + 32]		; rbp
	mov	[rbx + 4096 + 72], rbp
	mov	rbp, [rax + 512 + 96]		; rax
	mov	[rbx + 4096 + 136], rbp

	or	dword [rbx + 8192 + event_mask], 1
@@:
	mov	rbx, [rax + 512 + 24]
	mov	rbp, [rax + 512 + 32]
	mov	rax, [rax + 512 + 96]

	; check if handler was called due to hadrware interrupt or with an "INT n" instruction
	btr	dword [sp_lapicT_flags], 3		; always resets bit 3
	jc	@f

	add	rsp, 120 + 32
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

	align 8
@@:	add	rsp, 120 + 32
	iretq



; we need to return number lapicT ticks to the caller so that it can schedule next timer
; so that resonable periodic timer can be achieved

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
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
	shr	rax, 1			; divide by 4 and round up
	adc	rax, 0
	shr	rax, 1
	adc	rax, 0

	;--- calculate for 1ms ----

	mov	r8, rax
	imul	rax, 1000000

	mov	edi, 1953125
	xor	edx, edx
	div	rdi			; eax = # of lapicT ticks each millisecond for the divider of 2

	xor	edi, edi
	not	edi
	mov	rsi, rdx
	cmp	rax, rdi
	ja	k64err

	shl	rsi, 32
	or	rax, rsi
	mov	[lapicT_ms], rax

	;--- calculate for 1us ----  (1ms = 1000us)

	mov	esi, 1000000
	mov	rax, r8
	imul	rax, rsi

	mov	esi, 1953125 * 1000
	xor	edx, edx
	div	rsi			; eax = # of lapicT ticks each microsecond for the divider of 2
	mov	rsi, rdx
	test	rax, rax
	jz	k64err

	shl	rsi, 32
	or	rax, rsi
	mov	[lapicT_us], rax

	pop	rbp rdi rsi rdx rcx rax
	ret

