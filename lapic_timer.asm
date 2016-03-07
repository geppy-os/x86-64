
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

	mov	r13d, [qword lapic + LAPICT_INIT]	;					R13
	mov	dword [qword lapic + LAPICT_INIT], -1	; TODO: mask timer, just in case

	mov	r15,	  [sp_lapicT_r15]
	mov	eax,	  [sp_lapicT_flags]
	movzx	ecx, word [sp_lapicT_currTID]
	shl	r15, 16

	; check if handler was called due to hadrware interrupt or with an "INT n" instruction
	test	eax, 1 shl 2				; 4
	jz	@f					; jump if no block to switch threads
	or	dword [sp_lapicT_flags], 1 shl 3	; 8
	test	eax, 1 shl 3
	jnz	k64err					; error if "INT n" was executed twice in a row

	; simply exit if no thread switch requested
	mov	dword [qword lapic + LAPICT_INIT], 0
	add	rsp, 120
	pop	rcx rax r13 r15
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq
@@:
	; calc address to save old thread registers
	imul	rcx, 0x10000 * 512
	cmp	rcx, 0
	jnz	@f
	lea	rcx, [registers]
@@:
	fxsave64 [rcx]
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

	mov	r14d, [qword lapic + LAPICT_CURRENT]	;					R14

;---------------------------------------------------------------------------------------------------
			    reg r13, 80f
	reg	[lapicT_flags], 40c

	add	[lapicT_time], r13d			; bring time up to date
	jnc	.check_last_timer			; jump if we don't need to switch the add_list

	; switch timer add_list = "lapicT_time" id, counter on add_list must be 0 if we did switch
	xor	dword [lapicT_flags], 10b
	or	dword [lapicT_flags], 10000b		; set bit to check counters later

	reg	[lapicT_flags], 40e

;---------------------------------------------------------------------------------------------------
.check_last_timer:
	; process timer list first - all timers have priority over regulary trigerred threads

	mov	ebp, [lapicT_flags]
	mov	eax, [lapicT_time]
	xor	ecx, ecx
	bt	ebp, 10b				; get lapicT_time ID (same as add_list ID)
	setc	cl
	xor	ecx, 1					; we'll use opposite(to add_list) list first

	cmp	[timers_local + TIMERS.cnt + rcx*8], 0	; check if counter =0 on outstanding list
	jnz	.process_timer				; process any outstanding timer right away
	reg	rcx, 10d
	xor	ecx, 1
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0	; then check counter on CURRENT list (add_list)
	jz	.process_priority

	; check time on non-outstanding timer list
	mov	ebp, [timers_local + TIMERS.head + rcx*8]
	mov	rsi, [timers_local + TIMERS.ptr]
	imul	ebp, sizeof.TIMER

mov rdi, [rbp + rsi + TIMER.wakeUpAt]
reg	rax, 100c
reg	rdi, 100a

	cmp	[rbp + rsi + TIMER.wakeUpAt], rax
	ja	.process_priority			; JUMP if closest timer time doesn't match

	; delete last timer entry, we'll switch to this thread
	;---------------------------------------------------------
.process_timer:

	reg	rcx, 10e

	mov	r8d, [timers_local + TIMERS.head + rcx*8]
	mov	rsi, [timers_local + TIMERS.ptr]
	mov	edi, r8d
	imul	r8d, sizeof.TIMER
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
	mov	r10, [rsi + r8 + TIMER.data2]		; r10
	mov	[rsi + r8 + TIMER.data2], r9
	mov	[timers_local + TIMERS.1stFree], edi

	; we'll pass this additional data when we switch to this thread:
	mov	r9,   [rsi + r8 + TIMER.data1]		; r9
	mov	r11,   [rsi + r8 + TIMER.returnPtr]	; r11
	movzx	r8d, [rsi + r8 + TIMER.gPID]		; r8

	mov	word [lapicT_currTID], 0;r8w
	xor	r11, r11

;---------------------------------------------------------------------------------------------------
	bt	dword [lapicT_flags], 4
	jnc	.run_timer

	xor	ecx, ecx
	bt	dword [lapicT_flags], 1
	;mov	 edi, 0
	setc	cl					; ecx = add_list id
	;or	 edi, ecx
	;xor	 edi, 1 				 ; edi = outstanding list (opposite to add_list)
reg rcx, 10e
	; add_list counter must be zero if we did switch the lists (no outstanding timers present)
	cmp	[timers_local + TIMERS.cnt + rcx*8], 0
	jnz	k64err

.run_timer:
	; timers run out-of-order for max 4ms
	mov	r10d, 4
	imul	r10d, [lapicT_ms]
	jmp	.exit


	; timer threads may be sleeping
	; we need to make sure they are on ready to run priority list, since 4ms won't be enough
	; if thread was sleeping - it can run full timeslice
	;
	; for device drivers we put thread on running list, so that next thread
	; switch goes to this thread (if thread requests)

;---------------------------------------------------------------------------------------------------

	align 8
.process_priority:

reg [lapicT_time], 834

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
	jz	k64err
	cmp	edi, 0xffff				; exit if non 0xffff thread index is found   EDI
	jz	.search_priorities

	mov	[lapicT_currTID], di
	mov	[lapicT_priQuene], esi


reg [lapicT_priQuene], 804

	imul	rdi, sizeof.THREAD
	xor	r11, r11				; RIP taken from thread control block
	movzx	eax, [threads + rdi + THREAD.time2run]
	xor	edx, edx
	mov	ebp, 1000
	mov	r8d, [lapicT_ms]
	div	ebp					; might've incorrectly calculated US so we use MS
	mov	r9d, [lapicT_us]
	imul	rax, r8
	imul	rdx, r9
	mov	ebp, 0xffffffff
	add	rax, rdx
mov eax, 0x24ff'ffff
	cmp	rax, rbp				; eax = 4byte # of lapic ticks
	jae	k64err
	mov	r10, rax

;---------------------------------------------------------------------------------------------------
.switch_timer_lists:									; di, cx, ax

; reg r13, 80a

;	 ; switch timer "add" lists if "lapicT_ms" overflows
;	 xor	 ecx, ecx
;	 bt	 dword [lapicT_flags], 1
;	 setc	 cl
;	 add	 [lapicT_time], r13d
;	 jnc	 .set_lapTimer
;
;;mov edi, [lapicT_time]
;;reg r13, 804
;
;	 xor	 edi, edi
;	 bt	 dword [lapicT_flags], 0
;	 setc	 dil					 ; edi = remove_list id
;	 xor	 ecx, 1 				 ; ecx = add_list id
;	 xor	 dword [lapicT_flags], 10b
;
	; need zero counter for add_list
	; remove_list id must not match new id of the add_list if remove_list counter !=0


	; first we add ticks to lapicT_time,   switch add list if needed, at the end of all check counters
; reg rcx, 20a
; reg rdi, 20a

;	 cmp	 edi, ecx				 ; jump if list IDs are not equal
;	 jnz	 @f
;	 cmp	 [timers_local + TIMERS.cnt + rdi*8], 0  ; check remove_list counter
;	 jnz	 k64err
;@@:	 cmp	 [timers_local + TIMERS.cnt + rcx*8], 0  ; check add_list counter
;	 jnz	 k64err


.set_lapTimer:

	;mov	 dword [qword lapic + LAPICT_INIT], 5




;---------------------------------------------------------------------------------------------------
.exit:							       ; r10 r14

	and	dword [lapicT_flags], not 10000b	; clear "did switch add_list" bit

	movzx	eax, word [lapicT_currTID]
	imul	rax, 0x10000 * 512
	cmp	rax, 0
	jnz	@f
	mov	r9d, [lapicT_kPML4]
	lea	rax, [registers]
	jmp	.switch
@@:
	lea	rdi, [rax + 8192]
	mov	rsi, 0xffff'fff0'0000'0000
	shr	rdi, 12
	or	rdi, rsi
	mov	r9, [rdi*8]

.switch:
	mov	rdi, 0x7fff'ffff'f000
	and	r9, rdi
	mov	cr3, r9

	test	r11, r11
	jnz	@f
	mov	r11, [rax + 512 + 120]			; rip
@@:
	mov	rsi, [rax + 512 + 128]
	mov	rbx, [rax + 512 + 136]
	mov	rbp, [rax + 512 + 144]
	mov	rdx, [rax + 512 + 152]

	mov	[rsp + 152], r11			; rip
	mov	[rsp + 160], rsi			; cs
	mov	[rsp + 168], rbx			; rflags
	mov	[rsp + 176], rbp			; rsp
	mov	[rsp + 184], rdx			; ss

	fxrstor64 [rax]

	; calculate aproximate time it takes to execute this handler, save into "lapicT_overhead"
	; Value inside "lapicT_overhead" is average of 2 executions of this handler
	mov	edi, dword [qword lapic + LAPICT_CURRENT]
	neg	r14d
	neg	edi
	xor	ecx, ecx
	lea	edi, [r14*2 + rdi + 2]
	cmp	dword [sp_lapicT_overhead], 0		; if we never ran this function, we double
	setz	cl					;     overhead to keep rest of the code happy
	shl	edi, cl
	add	dword [sp_lapicT_overhead], edi
	shr	dword [sp_lapicT_overhead], 1
	;mov	 edi, [sp_lapicT_overhead]
	;reg	 rdi, 60a

	mov	dword [qword lapic + LAPICT_INIT], r10d

	btr	dword [sp_lapicT_flags], 3		; always resets bit 3

	mov	r14, [rax + 512]
	mov	rdi, [rax + 512 + 8]
	mov	rsi, [rax + 512 + 16]
	mov	rbx, [rax + 512 + 24]
	mov	rbp, [rax + 512 + 32]
	mov	rdx, [rax + 512 + 40]
	mov	r8,  [rax + 512 + 48]
	mov	r9,  [rax + 512 + 56]
	mov	r10, [rax + 512 + 64]
	mov	r11, [rax + 512 + 72]
	mov	r12, [rax + 512 + 80]
	mov	rcx, [rax + 512 + 88]
	mov	r13, [rax + 512 + 104]
	mov	r15, [rax + 512 + 112]
	mov	rax, [rax + 512 + 96]

	jc	@f

	add	rsp, 120 + 32
	mov	dword [qword lapic + LAPIC_EOI], 0
	;mov	 eax, [qword lapic + LAPICT_CURRENT]
	;neg	 eax
	;reg	 rax, 60a
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

