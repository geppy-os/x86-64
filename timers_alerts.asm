
; Distributed under GPL v1 License
; All Rights Reserved.


;===================================================================================================
;   timer_at
;===================================================================================================
; input: r8  - time in special format (month/day
;	 r9  - ptr to entry point >=0, or 0 if suspend process and resume after timer fires
;	 r12 - data #1
;	 r13 - data #2
;     r14[0]   =1 if periodic

	align 8
timer_at:
	push	rax rcx rsi rdi



	pop	rdi rsi rcx rax
	ret

;===================================================================================================
;   timer_in	 alert in some time, for small delays only
;===================================================================================================
; input: r8 - time in microseconds that is <= 1 second
;	 r9  - ptr to entry point,
;	       OR 0 if suspend process and resume after timer fires (r12,r13,r14 ignored in this case)
;	 r12 - any user data #1
;	 r13 - any user data #2
;	 r14   != 0 if periodic

	align 8
timer_in:
	push	rax rdx rcx rsi rdi rbp rbx
	sub	rsp, 8
	cmp	r8, 0
	jle	.err
	cmp	r8, 1000*1000
	ja	.err

.got_free_enties:

	call	noThreadSw

	cmp	[timers_local + TIMERS.1stFree], -1
	jnz	.mem_ok

	call	resumeThreadSw

	push	r8 r9 r12 r13 r14

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
	call	alloc_linAddr
	jc	k64err.allocLinAddr		; need realloc without freeing already allocated mem

	pop	r14 r13 r12 r9 r8

	call	noThreadSw

	; TODO:
	; by this time "1stFree" might be different (!= -1)
	; different thread migh've used timer_in, so "1stFree" and timer list is totally unpredicatable

	; basically code bellow waiting for proper malloc & realloc fnctions

	mov	qword [timers_local + TIMERS.ptr], rax		; rax
	mov	dword [timers_local + TIMERS.blockSz], 16384	; ecx
	mov	dword [timers_local + TIMERS.1stFree], 0
	mov	dword [timers_local + TIMERS.cnt], 0
	mov	dword [timers_local + TIMERS.cnt2], 0
	; ? 2 heads
	; ? 2 counters

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

	; code above can take a while and so we see if we need to switch threads
	call   resumeThreadSw
	jmp    .got_free_enties

;---------------------------------------------------------------------------------------------------
	align 8
.mem_ok:
	xor	ecx, ecx
	bt	dword [lapicT_flags], 1
	mov	edi, [lapicT_time]
	setc	cl
	add	r8, rdi 		; += current time
	jnc	@f

	; switch timer list if overflow
	; counter and head depend on list switch (both modified by timer_insert)

	jmp k64err
	xor	dword [lapicT_flags], 10b  ; ???
	xor	ecx, 1			   ; ???

@@:
	; convert to milliseconds (return in EAX), with remainder in microseconds (return in R8D)
	mov	esi, 1000
	xor	eax, eax
	xor	edx, edx
	cmp	r8, rsi
	jb	@f
	mov	eax, r8d
	div	rsi
	mov	r8d, edx		; eax:r8d = ms:us
@@:
	shl	rax, 32
	or	r8, rax
	shl	rcx, 63
	mov	r14, r8

	push	r8
	or	r8, rcx 		; bit63
	lea	rbp, [timers_local]
	call	timer_insert
	pop	rbx

	mov	ecx, [lapicT_ms]
	mov	esi, [lapicT_us]
	mov	eax, ebx		; eax = microseconds
	shr	rbx, 32 		; ebx = milliseconds
	xor	ebp, ebp
	imul	rax, rsi
	not	ebp
	imul	rbx, rcx

	; both rax & rbx must be a 32bit value to fit into lapic timer
	cmp	rax, rbp
	ja	k64err
	cmp	rbx, rbp
	ja	k64err
	add	eax, ebx		; EAX = number of lapic timer ticks
	jc	k64err
	reg	rax, 803

	; if noThreadSw is active then nothing else can change variables bellow
	;----------------------------------------------------------------------

	bts	qword [k64_flags], 0	; if lapic timer active & counting (threads or timers or ...)
	jc	.reduce_task_time	; then we consider reducing time of currently running task

	or	byte [lapicT_flags], 1 shl 4		; we will entered lapicT handler due to timer
	mov	dword [lapicT_time], 0
	mov	[qword lapic + LAPICT_INIT], eax	; start lapic timer
	jmp	.ok

	;----------------------------------
.reduce_task_time:
	; if LAPICT_CURRENT above certain value then we consider reducing time of currently running task
	; if bellow then we let lapicT fire on its own
	; if =0 then resumeThreadSw will get us into the handler


	;actually,  need to get a lock for this:
	; 1)
	; if LAPICT_CURRENT > some_value
	; then
	;    do
	; else
	;    goto 2)
	;
	; if LAPICT_CURRENT   still >	some_value
	; then
	;    goto 2)
	; else
	;    goto 1)
	;
	; 2)

.ok:	clc
.exit:
	call	resumeThreadSw
	add	rsp, 8
	pop	rbx rbp rdi rsi rcx rdx rax
	ret
.err:
	stc
	jmp	.exit


; timer_in:
;
; even with 2 timer lists we won't be able to add timers eventually, and we'll have to
; put threads that add timers to sleep temporarily or we can let threads run and put "thread adding"
; operation on a quene
; !!! But we have very small timeout of 1second for "timer"in" function which is 0xF4240 microseconds
;     so, we should be able to finish timers on one list and switch to another
;
;		    but this depends how soon callers timer handler function is exited
;
;			 So, no periodic timers provided by the kernel, the act of adding
;			 another timer is when callers timer handler function can be interrupted
;
;  Still thread can have many timers that are added outside callers timer handler function.
;  These many timers limited by kernel timers counter.


;===================================================================================================
; timer_insert
;===================================================================================================
; input:  r8
;
; assume that all registers modified


	 align 8
timer_insert:
	cmp	dword [rbp + TIMERS.cnt], 0
	jz	.1st_entry

	mov	eax, [rbp + TIMERS.1stFree]
	mov	ecx, [rbp + TIMERS.head]
	mov	r10d, eax
	mov	ebx, ecx
	imul	eax, sizeof.TIMER
	imul	ecx, sizeof.TIMER
	mov	rdi, [rbp + TIMERS.ptr]
	mov	edx, [rbp + TIMERS.cnt]

	mov	esi, dword [rdi + rax + TIMER.data2]	; get next free entry

	mov	[rdi + rax + TIMER.returnPtr], r9
	mov	[rdi + rax + TIMER.data1], r12
	mov	[rdi + rax + TIMER.data2], r13
	mov	[rdi + rax + TIMER.wakeUpAt], r8

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
	cmp	[rbp + TIMERS.cnt], edx 		; counter is modified later on
	jnz	@f
	mov	[rbp + TIMERS.head], r10d
@@:
	; get and update "next" & "prev" of the current entry
	movzx	r8d, [rdi + rcx + TIMER.prev]
	mov	r9d, r8d				; r9 prev
	imul	r8d, sizeof.TIMER
	add	dword [rbp + TIMERS.cnt], 1
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

	mov	dword [rbp + TIMERS.head], eax
	mov	dword [rbp + TIMERS.1stFree], edi
	mov	dword [rbp + TIMERS.cnt], 1

	mov	[rsi + rcx + TIMER.returnPtr], r9
	mov	[rsi + rcx + TIMER.data1], r12
	mov	[rsi + rcx + TIMER.data2], r13
	mov	[rsi + rcx + TIMER.wakeUpAt], r8
	mov	[rsi + rcx + TIMER.next], ax
	mov	[rsi + rcx + TIMER.prev], ax
	jmp	.ok

;===================================================================================================

	align 8
timer_remove:

	  ; theres is a separate remove in lapic timer handler whch removes one entry - the "head"

	ret

;===================================================================================================
; for debugging purposes:

;macro asdP{
timer_list:
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
	ret
@@:
;}
