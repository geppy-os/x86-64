
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;    int_lapicTimer  -	switches threads, not a scheduler   ////////////////////////////////////////
;===================================================================================================
; !! LAPIC Timer is triggered because we need something new to run, not because something expired !!



	align 4
int_lapicTimer:
	or	dword [qword lapic + LAPICT], 1 shl 16

	add	byte [qword 0+txtVidMem], 1		; most top left symbol (next to it is RTC)
	push	r15 r13 rax rcx 			; 6 regs in RTC interrupt which shares stack
	sub	rsp, 120

	mov	eax, [sp_lapicT_flags]

	cmp	dword [qword lapic + LAPICT_INIT], 0xffff'fff0
	ja	k64err.lapT_largeInit

	; check if noThreadSw was called prior to entering this handler
	test	eax, 1 shl 2				; 4
	jz	@f					; jump if no "block" present to switch threads
	or	dword [sp_lapicT_flags], 1 shl 3	; 8
	test	eax, 1 shl 3
	jnz	k64err.lapT_doubleINT			; handler executed twice in a row with a block

	; simply exit if "no thread switch" was requested
	add	rsp, 120
	pop	rcx rax r13 r15
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

;---------------------------------------------------------------------------------------------------
	align 4
@@:
	mov	r13d, [qword lapic + LAPICT_INIT]	; INIT can be 0 			  R13
	sub	r13d, [qword lapic + LAPICT_CURRENT]	; if thread prematurely goes to sleep

	or	dword [qword lapic + LAPICT], 1 shl 16
	mov	dword [qword lapic + LAPICT_INIT], -1	; how long it takes to execute this handler ?

	mov	r15,	  [sp_lapicT_r15]
	movzx	ecx, word [sp_lapicT_currTID]
	shl	r15, 16
	mov	rax, 0x8000000000
	imul	rcx, rax				; address to save old thread registers

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
	bts	dword [lapicT_flags], 0 		; =1 when no TIMER entry on current timer_list id

	xor	ecx, ecx
	add	[lapicT_time], r13			; bring time up to date
	setc	cl
	or	[lapicT_redraw], cl
	shl	ecx, 1
	xor	dword [lapicT_flags], ecx		; time overflow = change of current timer_list id
	xor	r11, r11				; =0 if priority thread (no custom RIP addr)

	;-----------------------------------------------
	bt	dword [lapicT_flags], 1 		; get current timer_list id
	setc	cl

	;-------------------------------------------------------------------------------------------
	; We have 2 lists for timers. Determined by bit1 of "lapicT_flags";.
	;   "lapicT_time" is 8bytes and when it overflows we change bit 1 of "lapicT_flags".
	; Value of  "lapicT_flags[1]" bit determines in which list we add TIMER entries.
	;				    and from which list we remove TIMER entries.
	;-------------------------------------------------------------------------------------------
	; We only check timer_list after "lapicT_time" (and therefore timer_list_id bit) was adjusted.
	; If 4ms(run time without interruption) is not enforced by "timer_in" then late timers will
	; still fire but much later. Thats why we make sure (in "timer_in" func) that there are no
	; such timers on "timer_local"
	;-------------------------------------------------------------------------------------------
	; TODO: maybe we can check "timer_local" when exiting the timer handler
	;	   if there are timers (maybe for other threads) than can be missed
	;						    mainly during "lapicT_time" overflow


	cmp	[timers_local + TIMERS.cnt + rcx*8], 0	; check if counter =0
	jz	.process_priority_list

	; check time if counter is not 0
	mov	r8d, [timers_local + TIMERS.head + rcx*8]
	mov	rsi, [timers_local + TIMERS.ptr]
	mov	edi, r8d				; EDI - will be "1stFree"
	imul	r8d, sizeof.TIMER
	mov	rax, [lapicT_time]
	mov	rbx, [rsi + r8 + TIMER.wakeUpAt]	; rbx = time of next timer trigered thread

	btr	dword [lapicT_flags], 0
	cmp	rbx, rax
	ja	.process_priority_list			; JUMP if closest timer time doesn't match

;===================================================================================================
; we will be switching to a thread on timer list

	sub	[timers_local + TIMERS.cnt + rcx*8], 1

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

	mov	r9d, [timers_local + TIMERS.1stFree]	; where "1st free" points
	mov	r12, [rsi + r8 + TIMER.data2]		; r12					<<
	mov	[rsi + r8 + TIMER.data2], r9		; removed(freed) entry -> value of "1st free"
	mov	[timers_local + TIMERS.1stFree], edi	; "1st free" -> removed(freed) entry

	; we'll pass this additional data when we switch to this thread:
	movzx	r9d, [rsi + r8 + TIMER.gTID]		; r9
	mov	r13, [rsi + r8 + TIMER.data1]		; r13					<<
	mov	r11, [rsi + r8 + TIMER.handlerPtr]	; r11					<<

	mov	[lapicT_currTID], r9w

	; Time has matched for this TIMER entry. We have r11 - timer handler will work for max 4ms.
	; We ignore any other potential TIMER entries until timer handler exits.

	cmp	byte [rsi + r8 + TIMER.handlerPtr+7], 1 ; check if we only need to wake up thread
	jnz	.calc_timeslice 			; jump if not (valid time handler present)

	; at this point we are only waking threads from sleep:
	;     a) we'll use different RIP later, at the end where we exit lapicT_handler
	;     b) we won't exit into timer handler procedure
	;     c) correct small timeslice & immediate code execution will still be achieved

	; resume thread and put it back on priority list:

	mov	r8, threads
	mov	r10d, r9d
	imul	r9, sizeof.THREAD
	movzx	ebp, [r8 + r9 + THREAD.flags]		; get priority list ID, low 2 bits

	and	ebp, 1000'0011b
	btr	ebp, 7
	jnc	k64err.lapT_noThreadSleep		; jump if thread not sleeping
	and	word [r8 + r9 + THREAD.flags], 0xff7f

	cmp	word [lapicT_pri0 + rbp*2], -1
	jz	.one_entry

	movzx	edi, word [lapicT_pri0 + rbp*2] 	; next thread to run
	mov	esi, edi
	imul	edi, sizeof.THREAD
	movzx	eax, [r8 + rdi + THREAD.prev]		; next(1st) thread to run points to last to run
	mov	ecx, eax
	imul	eax, sizeof.THREAD

	; insert new thread to be last to run
	mov	[r8 + r9 + THREAD.prev], cx		; --> last to run
	mov	[r8 + r9 + THREAD.next], si		; --> 1st to run
	mov	[r8 + rdi + THREAD.prev], r10w		; 1st to run --> new
	mov	[r8 + rax + THREAD.next], r10w		; last to run --> new
	jmp	.calc_timeslice

.one_entry:
	mov	[lapicT_pri0 + rbp*2], r10w
	mov	[r8 + r9 + THREAD.next], r10w
	mov	[r8 + r9 + THREAD.prev], r10w
	jmp	.calc_timeslice

;===================================================================================================
; we will be switching to a priority thread

.process_priority_list:      ;TODO:	; maybe deivce driver priority can have many dev drivers (threads)
					; running as long as priority timeslice doesn't expire
				 ; all other priorities - one thread per one timeslice
				 ; dev drivers - many threads per one timeslice

	mov	esi, [lapicT_priQuene]			;	 12 10	e  c  a  8  6  4  2  0
	mov	ebp, 1111b				; dword (10'00'01'11'00'01'10'00'01'00b shl 8)
	xor	edx, edx				;	  2  0	1  3  0  1  2  0  1  0

.search_priorities:
	movzx	ecx, sil				; get index where to look for priority
	mov	edi, esi
	add	ecx, 8					; remove the index
	shr	edi, cl 				; low 2bits is the priority list number
	sub	ecx, 6					; switch to next index
	and	edi, 11b				; = priority list number
	btr	ebp, edi
	cmp	ecx, 9*2
	movzx	r9d, word [lapicT_pri0 + rdi*2] 	; get thread index
	cmova	ecx, edx
	mov	sil, cl 				;					     ESI
	cmp	r9d, 0xffff				; exit if non 0xffff thread index is found   EDI
	jnz	@f
	test	ebp, ebp				; exit if all priorities have been looked at
	jz	k64err.lapT_noThreads
	jmp	.search_priorities
@@:
	mov	[lapicT_priQuene], esi
	mov	[lapicT_currTID], r9w

;===================================================================================================
.calc_timeslice:

	movzx	r9d, word [lapicT_currTID]
	mov	eax, 4000				; 4ms = fixed timeslice for any timer handler
	test	r11, r11
	jnz	@f					; jump if thread is from timer list

	imul	r9d, sizeof.THREAD
	mov	eax, threads
	movzx	ecx, [rax + r9 + THREAD.next]
	movzx	eax, [rax + r9 + THREAD.time2run]
;mov rax,0x0fffffff
;mov rax,0x006fffff
;mov rax,0x0013ffff
	mov	[lapicT_pri0 + rdi*2], cx
@@:
	; convert microseconds to lapic timer ticks:
	xor	edx, edx				; convert to milliseconds first
	mov	esi, 1000				;     as they reduce runding error
	div	esi
	mov	r8d, [lapicT_ms]
	mov	r9d, [lapicT_us]
	imul	rax, r8
	imul	rdx, r9
	mov	esi, 0xffff'fff0
	add	rax, rdx
	mov	r10d, eax				; EAX  =  R10  = 4byte # of lapic ticks
	cmp	rax, rsi
	jae	k64err.lapT_manyTicks

	; compare desired timeout in R10 with any future TIMER trigered threads ;
	;     we could cut the mandatory 4ms run-without-interruption time	;
	;  "timer_in" function needs to make sure that no such timers present	;
	;-----------------------------------------------------------------------;
	; and we mess with the timeslice for priority trigerred threads - they	;
	; can potentially run for only a few lapicT ticks; < 1 microsecond :(	;
	;-----------------------------------------------------------------------;
	; anyhow, current non-timer thread must run just enough for a timer to
	; fire on time

	test	r11, r11				; if !=0 then timer runs for a 4ms max
	jnz	.exit					;   all other timers (if present) ignored

	bt	dword [lapicT_flags], 0
	jc	@f					; jump if no timer entry on curr list

	; At this point, we DO have future TIMER entry on CURRENT timer_list id
	; and we may or may not need to adjust current thread timeslice
	;-------------------------------------------------------------------------------------------
	; no need to worry about potential lapicT_time overflow earlier, its in the past

	mov	rcx, rbx				; rbx = 8byte "TIMER.wakeUpAt"
	sub	rbx, [lapicT_time]
	cmp	rbx, rsi
	jae	k64err.lapT_manyTicks

	cmp	ebx, eax
	cmovbe	r10d, ebx
	jmp	.exit
@@:
	; check potential timers on the opposite timer list
	; but no worries, if current timeslice doesn't overflow the time
	add	rax, [lapicT_time]
	jnc	.exit

	;-------------------------------------------------------------------------------------------
	xor	ecx, ecx
	bt	dword [lapicT_flags], 1
	setnc	cl					; get opposite/inverted timer_list id
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0	; check if counter =0
	jz	.exit

	mov	edi, [timers_local + TIMERS.head + rcx*8]
	mov	rsi, [timers_local + TIMERS.ptr]
	xor	rcx, rcx
	imul	edi, sizeof.TIMER
	not	rcx
	sub	rax, [lapicT_time]			; restore time-in, instead of time-at
	mov	rbx, [rsi + rdi + TIMER.wakeUpAt]
	sub	rcx, [lapicT_time]
	mov	esi, 0xffff'fff0

	;lea rbx, [rbx + rcx + 1]
	add	rcx, 1
	jc	.exit					; jump if lapicT_time=0
	add	rbx, rcx
	jc	.exit					; jump if result doesnt fit into 8byte val
	cmp	rbx, rsi
	ja	.exit					; large value means "wakeUpAt" on next timer
							;    list & "lapicT_time" are too far apart
	cmp	eax, ebx
	cmovb	r10d, eax

;===================================================================================================
.exit:
	cmp	r10, 0
	jle	k64err.lapT_manyTicks
	cmp	r10d, 0xffff'fff0
	ja	k64err.lapT_manyTicks

	; calculate from where to restore registers
	movzx	eax, word [lapicT_currTID]
	mov	rsi, threads
	mov	edi, eax
	mov	r9, 0x8000000000
	imul	edi, sizeof.THREAD
	imul	rax, r9 				; RAX
	mov	r9, qword [rsi + rdi + THREAD.pml4-2]
	mov	rbx, rax				; RBX  (512GB aligned, min 4KB in the future)
	shr	r9, 16

;===================================================================================================
;	update CR3, process timer events if any, update target exit point from this lapicT handler
.switch:
	mov	rdi, 0x7fff'ffff'f000			; we reload CR3 for system thread which can
	and	r9, rdi 				;	have all treads mapped at the same time
	mov	cr3, r9 				; switch to another thread PML4

	mov	rcx, [rax + 512 + 120]			; rip
	mov	rsi, [rax + 512 + 128]			; cs
	mov	rdi, [rax + 512 + 136]			; rflags
	mov	rbp, [rax + 512 + 144]			; rsp
	mov	rdx, [rax + 512 + 152]			; ss

	test	r11, r11				; do we run new thread because of timer entry ?
	jz	.priority_thread			; jump if no (R11 = 0 or next RIP where we jump)
	rol	r11, 8
	cmp	r11b, 1 				; are we simply waking up a thread ?
	jz	.priority_thread			; jump if yes
	ror	r11, 8

							; DIFFERENT: but timer_exit function still needs
							;   to restore previous sleep state
							;   if different timer fired while we are
							;   sleeping with a timeout
	mov	[rbx + 4096], rcx
	mov	[rbx + 4096 + 8], rsi
	mov	[rbx + 4096 + 16], rdi
	mov	[rbx + 4096 + 24], rbp
	mov	[rbx + 4096 + 32], rdx
	or	rbx, 1					; use bit0 due to lack of registers							   ; normally RBX is 512GB aligned (min 4KB in future)
.sz=32
	; can get #PF as soon as we touch user stack
	sub	rbp, .sz
	mov	qword [rbp], .sz			; number of bytes before "iret" frame
	mov	qword [rbp + 8], r13			; user data1
	mov	qword [rbp + 16], r12			; user data2
	mov	qword [rbp + 24], 0			; user data3
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

	mov	dword [qword lapic + LAPICT_INIT], -1
	and	dword [qword lapic + LAPICT], not (1 shl 16)	; enable interrupt delivery
	mov	rcx, cr0					; serializing instr, probably not needed
	mov	dword [qword lapic + LAPICT_INIT], r10d 	; new timeslice (must be reasonably large)
								;		!! currently not checked !!
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

	;--------------------------------------------------------------------------------------------
	; Timer handler always restores registers of prev event handler when timer handler is exited.
	; These regs will be destroyed if timer handler interrupted by a thread switch, or by running
	;								  timer handler proc
	; So we make another copy of these registers bellow.
	;--------------------------------------------------------------------------------------------

	btr	rbx, 0					; do we run thread because of new timer entry ?
	jnc	@f					; jump if no

	; save registers 2nd time for timer handler to restore

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

	or	dword [rbx + 8192 + event_mask], 1	; this mem location belongs to the thread
@@:							;	  but user thread can't modify it

	mov	rbx, [rax + 512 + 24]
	mov	rbp, [rax + 512 + 32]
	mov	rax, [rax + 512 + 96]

	; check if handler was called due to hadrware interrupt or with an "INT n" instruction
	btr	dword [sp_lapicT_flags], 3		; always resets bit 3
	jc	@f
	;bt	 dword [qword lapic + 0x110], 0
	;jnc	 k64err 				; bit set if IRQ triggered by lapic

	add	rsp, 120 + 32
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

	align	4
@@:	;bt	 dword [qword lapic + 0x110], 0 	; bit clear if IRQ fired using "int" instruction
	;jc	 k64err
	add	rsp, 120 + 32
	iretq

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

	align 4
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


