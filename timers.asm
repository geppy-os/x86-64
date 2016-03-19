
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;   timer_at
;===================================================================================================
; input: r8  - time in special format (month/day
;	 r9  - ptr to entry point >=0, or 0 if suspend process and resume after timer fires
;	 r12 - data #1
;	 r13 - data #2


	align 8
timer_at:
	push	rax rcx rsi rdi



	pop	rdi rsi rcx rax
	ret

;===================================================================================================
;   timer_in	 alert in some time, for small delays only
;===================================================================================================
; input: r8  - time in microseconds  <= 1 second
;	 r9  - ptr to entry point,
;	       OR 0 if suspend process and resume after timer fires (r12,r13 ignored in this case)
;	 r12 - any user data #1
;	 r13 - any user data #2

	align 8
timer_in:
	push	rax rdx rcx rsi rdi rbp rbx
	cmp	r8, 10				; min 10us
	jb	.err
	cmp	r8, 1000*1000			; max 1s
	ja	.err

	; convert to milliseconds + microseconds first, then to lapic timer ticks
	; not sure how accurate lapic_timer ticks per microsecond are
	; The milliseconds simply reduces rounding errors.
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
	add	rax, rcx			; eax = lapic timer ticks
	cmp	rax, 0x6fff'ffff		;	must not exceed 0x6fff'ffff
	ja	k64err.timerIn_manyLapTicks

	;-------------------------------------------------------------------------------------
@@:
	call	noThreadSw
	cmp	[timers_local + TIMERS.1stFree], -1
	jnz	@f

	call	resumeThreadSw

	push	rax r8 r9 r12 r13 r14

	call	timer_memAlloc

	pop	r14 r13 r12 r9 r8 rax

	jmp	@b
@@:
	;-------------------------------------------------------------------------------------
	push	rax

	xor	r14, r14
	bt	dword [lapicT_flags], 1      ; counter 0 ??? on new list
	mov	r8d, [lapicT_time]
	setc	r14b
	add	r8d, eax			; += current time
	jnc	@f

	; switch timer list if overflow (counter for new add_list must be 0)
	mov	rax, [timers_local + TIMERS.ptr]
	xor	r14, 1
	xor	dword [lapicT_flags], 10b
	cmp	[timers_local + TIMERS.cnt + r14*8], 0
	jnz	k64err.timerIn_timerCntNot0
@@:
	push	r8
	lea	rbp, [timers_local]
	call	timer_insert
	pop	rax				; time-at (adjusted to current local time)   rax
	pop	r8				; time-in (original input in lapicT ticks)	r8

	;-------------------------------------------------------------------------------------------
	; we are running on behalf of some thread and we are adding timer for the same thread
	; we can simply put a new value into LAPICT_INIT after updating lapicT_time
	; if noThreadSw is active then none of the vars are changed except bit3 in lapicT_flags
	;-------------------------------------------------------------------------------------------

; device ints can still fire, and so what?

	cmp	dword [qword lapic + LAPICT_INIT], 0
	jz	@f
	cmp	r8d, [qword lapic + LAPICT_CURRENT]
	jae	.ok					; need >= left, lapicT handler handles timeouts
@@:
	or	dword [qword lapic + LAPICT], 1 shl 16	; mask timer, won't let it fire
	mfence
	bt	dword [lapicT_flags], 3
	jc	.ok					; jump if managed to fire before we masked it

	mov	edi, [qword lapic + LAPICT_INIT]
	sub	edi, [qword lapic + LAPICT_CURRENT]	; init_0 - current_? = 0
reg rdi, 10c2
	add	[lapicT_time], edi
	jnc	@f

	; shall we remove potential timers ?? hmm ? can they exist on new add_list id that we switched?

	xor	ecx, ecx
	btc	dword [lapicT_flags], 1
	setnc	cl
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0
	jnz	k64err.timerIn_timerCntNot0_1
@@:
	mov	dword [qword lapic + LAPICT_INIT], -1		; very large value for timer
	and	dword [qword lapic + LAPICT], not (1 shl 16)	; unmask timer = generate interrupt
	mov	dword [qword lapic + LAPICT_INIT],r8d		; reasonable value for timer

	;-------------------------------------------------------------------------------------------
.ok:	and	dword [qword lapic + LAPICT], not (1 shl 16)
	clc
@@:	call	resumeThreadSw
	pop	rbx rbp rdi rsi rcx rdx rax
	ret
.err:
	stc
	jmp	@b


;===================================================================================================
;   timer_insert
;===================================================================================================
; input:  r8
;
; assume that all registers modified


	 align 8
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

	mov	[rdi + rax + TIMER.returnPtr], r9
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
	align 8
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

	mov	[rsi + rcx + TIMER.returnPtr], r9
	mov	[rsi + rcx + TIMER.data1], r12
	mov	[rsi + rcx + TIMER.data2], r13
	mov	[rsi + rcx + TIMER.wakeUpAt], r8
	mov	[rsi + rcx + TIMER.next], ax
	mov	[rsi + rcx + TIMER.prev], ax
	mov	[rsi + rcx + TIMER.gTID], r11w
	jmp	.ok

;===================================================================================================
;
;	 align 8
;timer_remove:
;
;	   ; theres is a separate remove in lapic timer handler whch removes one entry - the "head"
;
;	 ret

;===================================================================================================
;   timer_memAlloc
;===================================================================================================

	align 8
timer_memAlloc:

	; code bellow is waiting for a proper "malloc" fnction, and "mem_free"

	push	r8 r9 r12 r13 r14

	lea	rbp, [timers_local]
	mov	rax, [rbp + TIMERS.ptr] 	; could be 0, ok
	mov	r9d, [rbp + TIMERS.blockSz]
	mov	r8, rax
	mov	ecx, r9d
	add	r9d, 16384
	shr	r8, 14
	shr	r9d, 14

	mov	rax, 0xa00000/16384
	mov	r9, 0x200000/16384
	mov	r8, rax
	shl	rax, 14
	mov	r12d, PG_P + PG_RW + PG_ALLOC
	call	alloc_linAddr
	jc	k64err.allocLinAddr		; need realloc without freeing already allocated mem

	pop	r14 r13 r12 r9 r8

	call	noThreadSw

	; TODO:
	; by this time "1stFree" might be different (!= -1)
	; different thread migh've used timer_in, so "1stFree" and timer list is totally unpredictable


	mov	qword [timers_local + TIMERS.ptr], rax		; rax
	mov	dword [timers_local + TIMERS.blockSz], 16384	; ecx
	mov	dword [timers_local + TIMERS.1stFree], 0
	mov	dword [timers_local + TIMERS.cnt], 0
	mov	dword [timers_local + TIMERS.cnt2], 0

	; setup free entries:

	mov	esi, 16384/sizeof.TIMER - 1
	mov	ecx, 1
@@:
	mov	[rax + TIMER.data2], rcx		; temp next free entry
	add	rax, sizeof.TIMER
	add	ecx, 1
	sub	esi, 1
	jnz	@b

	xor	ecx, ecx
	not	rcx
	mov	[rax + TIMER.data2], rcx

	call   resumeThreadSw

	ret

;===================================================================================================
; for debugging purposes:

macro asd{
timer_list:
	pushf
	push	rax rcx rdx rsi rbp r8 r9
	lea	rbp, [timers_local]
	mov	ecx, [rbp + TIMERS.cnt]
	mov	rsi, [rbp + TIMERS.ptr]
	mov	eax, [rbp + TIMERS.head]
	mov	edx, [rbp + TIMERS.1stFree]
	reg	rcx, 404			; counter
	reg	rax, 404				 ; head
	reg	rdx, 404				       ; 1stFree

@@:
	sub	ecx, 1
	jc	@f
	imul	eax, sizeof.TIMER
	mov	r8, [rsi + rax + TIMER.wakeUpAt]
	mov	r9d, dword [rsi + rax + TIMER.next]
	reg	r8, 100b
	reg	r9, 80a
	movzx	eax, r9w
	jmp	@b
@@:
	pop	r9 r8 rbp rsi rdx rcx rax
	popf
	ret
}
