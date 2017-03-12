
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; timer handler needs to restore all registers used (saving is done by lapicTimer handler)
; Timer handler needs to restore prev state of the thread: sleep or not sleep

	align 4
timer_exit:
	cli						; maybe can use noThreadSw here
	mov	rax, cr8				;   and cli at the end, before iret
	sub	rsp, 40

	mov	r15, 0x400000

	movzx	r13d, word [lapicT_currTID]
	mov	rax, 0x8000000000
	imul	r13, rax

	btr	dword [r13 + 8192 + event_mask], 0

	fxrstor [r13 + 4096 + 192]

	mov	rdi, [r13 + 4096]
	mov	rsi, [r13 + 4096 + 8]
	mov	rbx, [r13 + 4096 + 16]
	mov	rbp, [r13 + 4096 + 24]
	mov	rdx, [r13 + 4096 + 32]
	mov	[rsp], rdi				; rip
	mov	[rsp + 8], rsi				; cs
	mov	[rsp + 16], rbx 			; rflags
	mov	[rsp + 24], rbp 			; rsp
	mov	[rsp + 32], rdx 			; ss

	mov	r14, [r13 + 4096 + 40]
	mov	rdi, [r13 + 4096 + 48]
	mov	rsi, [r13 + 4096 + 56]
	mov	rbx, [r13 + 4096 + 64]
	mov	rbp, [r13 + 4096 + 72]
	mov	rdx, [r13 + 4096 + 80]
	mov	r8, [r13 + 4096 + 88]
	mov	r9, [r13 + 4096 + 96]
	mov	r10, [r13 + 4096 + 104]
	mov	r11, [r13 + 4096 + 112]
	mov	r12, [r13 + 4096 + 120]
	mov	rcx, [r13 + 4096 + 128]
	mov	rax, [r13 + 4096 + 136]
	mov	r15, [r13 + 4096 + 152]
	mov	r13, [r13 + 4096 + 144]

	iretq


;===================================================================================================
;   timer_in  -  alert in some time, for small delays only   ///////////////////////////////////////
;===================================================================================================
; running this func will interfere with time during which current thread is running without
; accounting the difference anywhere (like in lapicTimer interrupt handler for a example)
;-------------------------------------------------------------------------------------------------
; input: r8  - time in microseconds  <= 1 second
;	 r9  - valid pointer to entry point
;	 r12 - any user data #1
;	 r13 - any user data #2

	align 4
timer_in:
	push	rax rdx rcx rsi rdi rbp rbx r14 r9
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	bts	qword [r14 + 8192 + functions], FN_TIMER_IN


	cmp	r8, 10					; min 10us
	jb	k64err.timerIn_min10us
	cmp	r8, 1000*1000				; max 1s
	ja	k64err.timerIn_max1s

	mov	r15, 0x400000

.minDelay = 20 ; in lapic timer ticks

	; convert to milliseconds + microseconds first, then to lapic timer ticks
	; The milliseconds simply reduce rounding errors later (lapic_ticks per ms).
	mov	esi, 1000
	xor	eax, eax
	xor	edx, edx
	mov	eax, r8d
	div	rsi
	mov	edi, [lapicT_ms]
	mov	esi, [lapicT_us]
	mov	ecx, edx
	imul	rax, rdi
	imul	rcx, rsi
	mov	edi, 0xffff'fff0
	add	rax, rcx				; eax = lapic timer ticks

	cmp	rax, rdi
	ja	k64err.timerIn_manyLapTicks
	cmp	eax, .minDelay
	jb	k64err.timerIn_manyLapTicks

;---------------------------------------------------------------------------------------------------
	call	noThreadSw
	or	dword [qword lapic + LAPICT], 1 shl 16	; Mask timer.
	mov	rcx, cr0
	push	rax

	; by the way, "lapicT_time" will overflow max 1 time if we add multiple 4byte values to it.

	mov	ebp, [qword lapic + LAPICT_INIT]	; INIT wont change while this func is running
	mov	ebx, [qword lapic + LAPICT_CURRENT]	; INIT >= LAPICT_CURRENT (CURRENT counts down)
	mov	edi, ebp
	sub	edi, ebx				; if INIT=0 then CURRENT also =0

	; this avoids some race conditions
	cmp	ebx, .minDelay				; if leftover LAPICT_CURRENT is at critical
	ja	@f
	mov	edi, ebp				;      then assume thread ran its
	xor	ebx, ebx				;	 full timeslice already
	;mov	[qword lapic + LAPICT_INIT], 0
@@:
	; account for elapsed time as usual
	xor	ecx, ecx
	add	[lapicT_time], rdi			; TODO: need update other thread info - same place where update time
	setc	cl
	or	[lapicT_redraw], cl
	shl	ecx, 1
	xor	[lapicT_flags], ecx			; change current timer_list id if overflow
	push	rbx					; how many ticks left

	; TIMER entry goes on opposite list if there is future time overflow for the timer.
	; (to simplify logic and code we dont check if that list is empty or not)
	xor	r14, r14
	bt	dword [lapicT_flags], 1 		; get timer list id
	mov	r8, [lapicT_time]
	setc	r14b					; save timer list id into R14
	add	r8, rax 				; time += time offset
	adc	r14d, 0 				; time overflow ?
	and	r14d, 1 				; 0 + 1(cf) and 1 = 1  ;;;  1 + 1(cf) and 1 = 0

	lea	rbp, [timers_local]
	call	timer_insert
	pop	rbx					; lapicT ticks left (=LAPICT_CURRENT)
	pop	r8					; time-in (original input in lapicT ticks)
	jc	k64err.timerIn_insert

	cmp	byte [rsp+7], 0x01			; do we want to sleep? top byte of the handler
	jnz	.no_sleep

;---------------------------------------------------------------------------------------------------
;///////////////////////   stop timer, run next thread
;---------------------------------------------------------------------------------------------------
; Current thread is going to sleep. Switch to sheduler right away - it'll see timer entry and set for
; current thread to wake up. Meanwhile some other priority thread will be running.


	movzx	r8d, word [lapicT_currTID]
	call	thread_sleep.sleep			; r8 is the only input

	mov	dword [qword lapic + LAPICT_INIT], 0
	mov	rax, cr0

	; unconditional "resumeThreadSw" function:
	and	dword [lapicT_flags], not 4		; disable request to stop thread switch
	mov	rax, cr0				; serializing instr. (AND executed before OR)
	or	dword [lapicT_flags], 1 shl 3		; skip EOI

	mov	rax, cr0
	and	dword [qword lapic + LAPICT], not( 1 shl 16)

	mov	rax, cr0

	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	btr	qword [r14 + 8192 + functions], FN_TIMER_IN
	int	LAPICT_vector				; fire lapicT handler that needs to reenable ints

	; We'll return here after some time and quit this function and maybe quit syscall as needed
	; Timer will put thread on ready-to-run list and return here intead of timer handler proc
	; Code bellow will still use very short timeslice - as meant for a timer handler

	; ?? but until we return here we will be in a syscall with unrestored registers ??
	;   how many simultaneous syscalls like that ?
	; we could save these regs somewhere else

	clc
	jmp	.exit2

;---------------------------------------------------------------------------------------------------
;///////////////////////  continue running current thread as leftover timeslice allows
;---------------------------------------------------------------------------------------------------
.no_sleep:
	cmp	ebx, r8d				; Chose smallest interval and set it. Either
	cmovb	r8d, ebx				; timer-in value or time left for trhread to run

	; we put a new value into LAPICT_INIT to interrupt current thread at different time
	mov	rax, cr0
	mov	dword [qword lapic + LAPICT_INIT], -1		; very large value for timer
	and	dword [qword lapic + LAPICT], not (1 shl 16)	; unmask timer = generate interrupt
	  ; SMI is the only problem, and only if it
	  ;	saves (or restores) CPU state for around 0xffff'ffff lapic ticks
	mov	rax, cr0
	mov	dword [qword lapic + LAPICT_INIT],r8d		; reasonable value for timer
	mov	rax, cr0

	; if r8=0 then lapicTimer is stopped and will never fire
	;    need to setup enviroment to trigger lapicT manually and correctly
	test	r8d, r8d
	jnz	.ok

	; "resumeThreadSw" will now manually trigger "lapicT_hanlder"
	bts	dword [lapicT_flags], 3

.ok:	clc
.exit:	call	resumeThreadSw
.exit2:
	pushf
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	btr	qword [r14 + 8192 + functions], FN_TIMER_IN
	popf

	pop	r9 r14 rbx rbp rdi rsi rcx rdx rax
	ret
.err:
	stc
	jmp	.exit2


;===================================================================================================
;   timer_insert   /////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input:  r14, rbp (for the function to work correctly)
;	  r8, r12, r13, r9  (user input data)
;---------------------------------------------------------------------------------------------------
; assume that all registers modified
; function must not use "resumeThreadSw" function
;-------------------------------------------------------------------------------------------------

; TODO: need to ensure that timer entries are 4ms apart !
;				previous and next extries
;	otherwise need some local queue

	 align 4
timer_insert:
	cmp	dword [rbp + TIMERS.cnt + r14*8], 0
	jz	.1st_entry

	mov	eax, [rbp + TIMERS.1stFree]
	mov	ecx, [rbp + TIMERS.head + r14*8]
	mov	r10d, eax
	mov	ebx, ecx
	imul	eax, sizeof.TIMER
	imul	ecx, sizeof.TIMER
	mov	rdi, [rbp + TIMERS.ptr]
	mov	edx, [rbp + TIMERS.cnt + r14*8]

	mov	esi, dword [rdi + rax + TIMER.data2]	; get next free entry
	mov	r11w, [lapicT_currTID]

	mov	[rdi + rax + TIMER.handlerPtr], r9
	mov	[rdi + rax + TIMER.data1], r12
	mov	[rdi + rax + TIMER.data2], r13
	mov	[rdi + rax + TIMER.wakeUpAt], r8
	mov	[rdi + rax + TIMER.gTID], r11w

	mov	[rbp + TIMERS.1stFree], esi

@@:	; start search from the "head" at RCX offset
	cmp	[rdi + rcx + TIMER.wakeUpAt], r8
	jae	@f
	movzx	ecx, [rdi + rcx + TIMER.next]
	imul	ecx, sizeof.TIMER
	sub	edx, 1
	jnz	@b
@@:
	; change "head" if needed
	cmp	[rbp + TIMERS.cnt + r14*8], edx 	; counter is modified later on
	jnz	@f
	mov	[rbp + TIMERS.head + r14*8], r10d
@@:
	; get and update "next" & "prev" of the current entry
	movzx	r8d, [rdi + rcx + TIMER.prev]
	mov	r9d, r8d				; r9 prev
	imul	r8d, sizeof.TIMER
	add	dword [rbp + TIMERS.cnt + r14*8], 1
	movzx	r12d, [rdi + r8 + TIMER.next]		; r12 next
	mov	[rdi + rax + TIMER.prev], r9w
	mov	[rdi + rax + TIMER.next], r12w

	; update previous and next entries
	mov	[rdi + r8  + TIMER.next], r10w
	mov	[rdi + rcx + TIMER.prev], r10w

.ok:	clc
.exit:
	ret

;---------------------------------------------------------------------------------------------------
	align 4
.1st_entry:
	mov	eax, [rbp + TIMERS.1stFree]
	mov	rsi, [rbp + TIMERS.ptr]
	mov	ecx, eax
	imul	rcx, sizeof.TIMER
	mov	edi, dword [rsi + rcx + TIMER.data2]	; get next free entry

	mov	r11w, [lapicT_currTID]
	mov	dword [rbp + TIMERS.head + r14*8], eax
	mov	dword [rbp + TIMERS.1stFree], edi
	mov	dword [rbp + TIMERS.cnt + r14*8], 1

	mov	[rsi + rcx + TIMER.handlerPtr], r9
	mov	[rsi + rcx + TIMER.data1], r12
	mov	[rsi + rcx + TIMER.data2], r13
	mov	[rsi + rcx + TIMER.wakeUpAt], r8
	mov	[rsi + rcx + TIMER.next], ax
	mov	[rsi + rcx + TIMER.prev], ax
	mov	[rsi + rcx + TIMER.gTID], r11w
	jmp	.ok

