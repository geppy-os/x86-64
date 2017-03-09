
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;   thread_fromFile   //////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8	   = address of properly prepeared executable file
;	 r9[7:0]   =1 if run in ring3, =2 if run in ring0, =anything_else - use default
;	 r9[15:8]  = priority list id
;	 r12d	   if =0 then thread won't be scheduled to run right away
;		   if !=0 then r12 points to a set of data that will be copied to the thread
; return: r8 = thread id
;---------------------------------------------------------------------------------------------------

	align 4
thread_fromFile:
	push	rax rcx rsi rdi rbp
	sub	rsp, .vars

.vars		= 48
.allowed_flags	= PG_USER


	mov	rsi, r8
	mov	[rsp], r8
	mov	[rsp + 8], r9d
	mov	[rsp + 40], r12
	cmp	dword [r8 + 12], "_OK_"
	jnz	k64err

	call	thread_allocID
	jc	.err
	mov	[rsp + 12], r8d
	mov	qword [rsp + 16], PG_USER
	reg	r8, 26a

			  ; currently, skipping uninitialized data section


	mov	eax, [rsi + 36] 			; file length, >0
	add	eax, (64+8)*1024			; 64KB header + extra 8KB to align code section
	add	eax, 0x1fffff
	and	eax, not 0x1fffff
	shr	eax, 12 				; 2MB aligned size in 16KB units

	imul	r8, 0x10000 * 512			; r8 *= 512GB in 16KB units
	lea	rbp, [r8 + 0x10000*512] 		; stack is at the end of 512GB
	mov	rcx, r8

	; alloc space for control block and code
	mov	r12, [rsp + 16]
	mov	r9, rax
	or	r12, PG_P + PG_RW + PG_ALLOC		; "PG_RW" to copy code, removed after that
	call	alloc_linAddr
	jc	k64err

	; alloc space for the stack
	mov	r12, [rsp + 16]
	lea	r8, [rbp - 0x80]
	or	r12, PG_P + PG_RW + PG_ALLOC + PG_MORE_STACK
	mov	r9d, 0x200000/16384
	or	r12, [feature_XD]
	call	alloc_linAddr
	jc	k64err

	shl	rbp, 14 				; "end of stack" linear address      RBP
	shl	rcx, 14 				; thread "header" linear address	 RCX

	; alloc PML4 for new thread
	lea	rax, [rsp + 24] 			; [rsp+16]  phys pml4 addr
	push	rax 1
	call	alloc4kb_ram
	lea	rsp, [rsp + 16]
	jc	k64err

	; two #PFs coming up here (TODO: change or comment)
	;mov	 r9, 512*1024*1024*1024 		 ; 512GB
	;mov	 r8d, [rsp + 12]
	;imul	 r8, r9 				 ; thread id * 512GB
	;test	 [r8], r8
	;test	 [r8 + r9 - 8], r8

;---------------------------------------------------------------------------------------------------
	call	noThreadSw

	; map PML4 to temporary location
	mov	rsi, [rsp + 24]
	lea	rdi, [clonePML4]
	btr	rsi, 63
	mov	r12, 0xffff'fff0'0000'0000
	ror	rdi, 12
	or	rsi, PG_P+PG_RW
	or	r12, rdi
	rol	rdi, 12
	mov	[r12 * 8], rsi
	invlpg	[rdi]

	; zero new pml4 if needed (at RDI pointer)
	mov	rsi, rcx
	cld
	xor	eax, eax
	mov	ecx, 4096/8
	rep	stosq
	mov	rcx, rsi

	; copy 1 system thread pml4e & 1 pml4e that belongs to new thread
	; copy these 2 from pml4 that is currently in use by system thread

	movzx	r8, word [lapicT_sysTID]		; system thread id = sys thread pml4 entry
	mov	r9d, [rsp + 12] 			; new thread id = new thread pml4 entry
	mov	rax, 0xffff'ffff'ffff'f000
	mov	rsi, [rax + r8*8]
	mov	rdi, [rax + r9*8]
	mov	rax, [rax + 511*8]
	mov	[clonePML4 + r8*8], rsi
	mov	[clonePML4 + r9*8], rdi
	mov	[clonePML4 + 511*8], rax

	; delete temporary mapping
	mov	qword [r12 * 8], 0
	invlpg	[clonePML4]

	call	resumeThreadSw

;---------------------------------------------------------------------------------------------------
; Newly created thread always occupies unique linear addrs - we can continue without certain locks.

	mov	r8, [rsp]
	mov	edi, [r8 + 36]
	sub	edi, [r8 + 8]				; fileSz-codeSz = data+exports+imports+header
	mov	eax, edi
	neg	edi
	and	edi, 4095
	mov	esi, edi
	add	eax, edi

	lea	rax, [rcx + 64*1024 + rax]		; skip header added by OS
	pushfq
	pop	r9

	mov	qword [r8 + 16], rax			; code section addr, where file checksum was
	mov	qword [rcx + 512 + 120], rax		; rip
	mov	qword [rcx + 512 + 128], 8		; cs
	mov	qword [rcx + 512 + 136], r9		; rflags
	mov	qword [rcx + 512 + 144], rbp		; rsp	     ---- used
	mov	qword [rcx + 512 + 152], 0x10		; ss

	; copy header+stuff to an addr, and copy code to a 4KB aligned address
	lea	rdi, [rcx + 64*1024 + rsi]
	lea	r9, [rcx + 64*1024]
	mov	rsi, r8
	mov	ecx, [r8 + 36]				; total file length
	rep	movsb

	;----------------------------------------------------------
	; use "mem_setFlags" to change code/data permissions ...
	; ...

	mov	r8, [rsp + 40]
	test	r8, r8
	jz	.exit

	mov	rax, [r8]
	mov	[r9 - 8], rax


	; let schedule know that there is another thread to run
	mov	r8d, [rsp + 12]
	mov	r9, [rsp + 24]
	mov	r12d, 65500
	xor	r13, r13
	call	thread_addEntry
	jc	.err
	; CF=0

.exit:	mov	rbp, [rsp + .vars]
	mov	rdi, [rsp + .vars+8]
	mov	rsi, [rsp + .vars+16]
	mov	rcx, [rsp + .vars+24]
	mov	rax, [rsp + .vars+32]
	lea	rsp, [rsp + .vars+40]
	ret
.err:
	stc
	jmp	.exit

;===================================================================================================
;   thread_createSys
;===================================================================================================
; sets initial variables, called only once by each CPU before this CPU timer even running

	align 4
thread_createSys:

	; ---- to be deleted ---------------------------------------
	mov	dword [qword 160*24+txtVidMem], 0x0e300e30
	mov	dword [qword 160*24+4+txtVidMem], 0x0e300e30
	mov	byte [qword 0+txtVidMem], 0x30
	mov	word [qword 160*24+txtVidMem + 32], '0 '
	mov	word [qword 160*24+txtVidMem + 36], '0 '
	mov	word [qword 160*24+txtVidMem + 40], '0 '
	mov	word [qword 160*24+txtVidMem + 44], '0 '
	mov	word [qword 160*24+txtVidMem + 48], '0 '
	mov	word [qword 160*24+txtVidMem + 52], '0 '
	mov	word [qword 160*24+txtVidMem + 56], '0 '
	;-----------------------------------------------------------

	; bit set - thread id available
	xor	eax, eax
	mov	rdi, gThreadIDs
	mov	ecx, 256/8/8					; future limit will be 512 threads
	not	rax
	cld
	rep	stosq
	;-----------------------------------------------------------

	xor	eax, eax
	not	rax						; no threads in any priority group
	mov	[lapicT_pri0], rax				;   8bytes = four 2byte vars
	mov	[timers_local + TIMERS.1stFree], eax		; init timer list = no timers

	call	thread_allocID					; each sys thread (on different CPU)
	jc	k64err						;    has unique id across entire OS
	;reg	 r8, 104a

	mov	edi, r8d
	mov	esi, threads
	imul	r8d, sizeof.THREAD
	mov	rbp, cr3

	; setup basic info for system thread entry (THREAD structure)
	mov	word [lapicT_pri0], di
	mov	word [lapicT_currTID], di
	mov    qword [rsi + r8 + THREAD.pml4], rbp
	;reg rbp, 101f
	mov	word [rsi + r8 + THREAD.next], di
	mov	word [rsi + r8 + THREAD.prev], di
	mov	word [rsi + r8 + THREAD.time2run], 65530	; timeslice in microseconds
	mov	word [rsi + r8 + THREAD.flags], 0		; bits[1:0] = priority list id
	mov	     [rsi + r8 + THREAD.return_RIP], 0
	mov	[lapicT_sysTID], di
								;14  12  10  e	c  a  8  4  2  0
	mov	dword [lapicT_priQuene], 0x87184'00		;  10'00'01'11'00'01'10'00'01'00b shl 8
								;   2  0  1  3	0  1  2  0  1  0

	;-------------------------------------------------------------------------------------------
	; alloc fixed size mem for per-cpu TIMER entries (=512 entries[1 per thread] * sizeof.TIMER)
	;-------------------------------------------------------------------------------------------

	mov	rax, 0xa00000/16384
	mov	r9, 0x200000/16384
	mov	r8, rax
	shl	rax, 14
	mov	r12d, PG_P + PG_RW + PG_ALLOC
	call	alloc_linAddr
	jc	k64err.allocLinAddr

	mov	qword [timers_local + TIMERS.ptr], rax
	mov	dword [timers_local + TIMERS.blockSz], 16384
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

	ret

;===================================================================================================
;    thread_sleep   -	put thread to sleep until an event happens or timeout expires  /////////////
;===================================================================================================
; input: r8  - thread id
;	 r9  - timeout in microseconds (up to 1 second); if =0 then wait for event only
;	       must be zero if putting other thread to sleep
;---------------------------------------------------------------------------------------------------
; Remove thread from ready-to-run priority list in order for the thread to sleep.
; If we get new events for the threads to process while prepearing to sleep - we resume thread after
; it was put to sleep. (???What about timer events???)
; SLEEP means SLEEP, no timer handlers, no executions until timeout expires or event happens
; If timeout present - function always returns to the caller after "thread_sleep" RIP address.
; Without timeout - this call of "thread_sleep" will never return
;		    unless its another thread that's going to sleep.

	align 4
thread_sleep:
	mov	r15, 0x400000

	push	rdi rsi rcx rax

	cmp	r8, 256
	jae	.err
	test	r9, r9					; easier with zero timeout
	jz	.no_timeout
	cmp	[lapicT_currTID], r8w			; non 0 timeout for self only
	jnz	.err

	pop	rax rcx rsi rdi

	mov	r8, r9
	mov	r9, 0x0100'0000'0000'0000
	xor	r12, r12
	xor	r13, r13
	jmp	timer_in

.no_timeout:
	; no thread swithes after this, (lapicT can fire but won't switch thread or fire timer handler)
	call	noThreadSw				;			    for current thread

	call	.sleep

	movzx	eax, word [lapicT_currTID]
	cmp	eax, r14d				; curr thread id (eax) & target thread id (r14)
	jnz	.ok					; jump if we are putting another thread to sleep
							;      (this thread wont schedule new stuff)
;---------------------------------------------------------------------------------------------------
; "lapicT_currTID" is going to sleep

	;add	 rsp, 5*8				 ; function won't return (POINTLES to adjust stack ??)

	or	dword [qword lapic + LAPICT], 1 shl 16	; mask lapic timer interrupt
	mov	rax, cr0				; serialization instruction

	; unconditional "resumeThreadSw" function:
	and	dword [lapicT_flags], not 4		; disable request to stop thread switch
	mov	rax, cr0				; serializing instr. (AND executed before OR)
	or	dword [lapicT_flags], 1 shl 3		; skip EOI
	int	LAPICT_vector				; fire lapicT handler that needs to reenable ints

	; code execution ends here
	jmp	k64err.thrd_sleep_afterINT20		; kernel panic

;---------------------------------------------------------------------------------------------------
; some other thread is going to sleep, func returns to caller

.ok:	clc
@@:	call	resumeThreadSw
.exit:	pop	rax rcx rsi rdi
	ret

.err:	stc
	jmp	.exit
.err2:	stc
	jmp	@b

;===================================================================================================
; input: r8d - thread id

	align 4
.sleep:

	mov	r14d, r8d				; R14 - thread id
	imul	r8, sizeof.THREAD
	mov	esi, threads
	movzx	edi, [rsi + r8 + THREAD.flags]		; get priority list ID, low 2 bits
	movzx	ecx, [rsi + r8 + THREAD.next]
	movzx	eax, [rsi + r8 + THREAD.prev]
	and	edi, 1000'0011b 			; bit7 =1 if already sleeping
	cmp	edi, 3
	ja	k64err.thread_sleep_already
	or	[rsi + r8 + THREAD.flags], 0x80 	; flag that thread is sleeping

	; If its a single entry on the priority list then we set the priority-list entry to 0xffff.
	; Otherwise we change prev/next THREAD structs pointed by thread entry that is to be moved
	;-------------------------------------------------------------------------------------------

	cmp	ecx, r14d				; jump if more than 1 thread on priority list
	jnz	@f
	cmp	ecx, eax				; if prev & next are the same (=0 threads)
	jnz	k64err.thread_sleep_invalidPrevNext
	mov	word [lapicT_pri0 + rdi*2], -1		;   then set entire priority list to 0xffff
	jmp	.done
@@:
	cmp	[lapicT_pri0 + rdi*2], r14w
	jnz	@f					; jump if 1st thread id != beeing suspended thread
	mov	[lapicT_pri0 + rdi*2], cx		;      otherwise update 1st thread id
@@:
	mov	r8d, ecx				; next
	mov	r9d, eax				; prev
	imul	r8d, sizeof.THREAD
	imul	r9d, sizeof.THREAD
	mov	[rsi + r8 + THREAD.prev], ax
	mov	[rsi + r9 + THREAD.next], cx
.done:
	ret

;===================================================================================================
;   thread_addEntry   //////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8d		thread id (max 255)
;	 r9		6byte pml4 physical addr
;
;	 r12d		time1 info
;	 r12[63:32]	time2 info
;
;	 r13b		id of the priority list (<= 3)
;	 r13[63:8]	undefined												  no errors reported
;---------------------------------------------------------------------------------------------------
; All registers preserved upon return (except input r8,r9,r12,r13).
; Once thread is put on a priority ready-to-run list - sheduler can pick this thread up and run it
; at any time, even before this function returns to caller.
; None of the input variables are checked to verify their correctness.
; New thread is added at the beginning of priority list.

	align 4
thread_addEntry:
	push	rax rcx rdi rbp rbx
	cmp	r8d, 256
	jae	.err
	test	r9, 0xfff
	jnz	.err
	cmp	r13b, 3
	ja	.err
	movzx	r13, r13b

	call	noThreadSw

	;reg	 r8, 40b
							; offs	idx
	movzx	eax, word [lapicT_pri0 + r13*2] 	; eax / ebp	first entry id
	mov	edi, r8d				; r8d / edi	new entry id
	mov	ecx, threads
	mov	ebp, eax
	imul	eax, sizeof.THREAD
	imul	r8d, sizeof.THREAD
	mov	[lapicT_pri0 + r13*2], di
	cmp	ebp, 0xffff
	jz	.1st_entry

	mov	qword [rcx + r8 + THREAD.pml4], r9
	mov	[rcx + r8 + THREAD.next], bp

	movzx	ebp, [rcx + rax + THREAD.prev]		; ebp / ebx	prev entry id
	mov	ebx, ebp
	imul	ebp, sizeof.THREAD
	mov	[rcx + rax + THREAD.prev], di		; old	first.prev -> new
	mov	[rcx + rbp + THREAD.next], di		; still last.next  -> new

	mov	[rcx + r8 + THREAD.prev], bx
	mov	[rcx + r8 + THREAD.time2run], r12w
	mov	[rcx + r8 + THREAD.flags], r13b 	; bits[1:0] = priority list id
	mov	[rcx + r8 + THREAD.return_RIP], 0
.ok:
	call	resumeThreadSw
	clc
@@:	pop	rbx rbp rdi rcx rax
	ret
.err:	stc
	jmp	@b

;---------------------------------------------------------
.1st_entry:
	mov	qword [rcx + r8 + THREAD.pml4], r9
	mov	[rcx + r8 + THREAD.next], di
	mov	[rcx + r8 + THREAD.prev], di
	mov	[rcx + r8 + THREAD.time2run], r12w
	mov	[rcx + r8 + THREAD.flags], r13b
	mov	[rcx + r8 + THREAD.return_RIP], 0
	jmp	.ok


;===================================================================================================
;    thread_allocID
;===================================================================================================
; return: r8 - thread id
;	  all other registers preserved
;	  CF=0 of success, CF=1 if failed(all IDs allocated already)

	align 4
thread_allocID:
	push	rbp rax rcx rsi

	cld
	mov	rbp, gThreadIDs_lock
	mov	rsi, gThreadIDs
	mov	ecx, -64
	and	r8d, [rbp]			; cache the cacheline with double access
	test	[rbp], ecx
	jmp	@f

.1:	call	resumeThreadSw
@@:	bt	dword [rbp], 0
	jc	@b
.2:	call	noThreadSw
	lock
	bts	dword [rbp], 0
	jc	.1

@@:
	cmp	ecx, MAX_THREAD 		; actual future limit will be 512
	jg	.err
	lodsq
	add	ecx, 64
	bsf	r8, rax
	jz	@b

	btr	rax, r8
	mov	[rsi-8], rax
	add	r8d, ecx
	clc
	sfence
;reg r8, 24e
.exit:
	mov	dword [rbp], 0
	call	resumeThreadSw
	pop	rsi rcx rax rbp
	ret
.err:	stc
	jmp	.exit


;===================================================================================================
;    thread_releaseID
;===================================================================================================
; input:  r8 = allocated thread id
; return: CF=0 on success, CF=1 if failed(ID not allocated)
;	  no registers are modified
;	  input r8 is preserved

	align 4
thread_releaseID:
	push	rbp rax rcx rsi
	cmp	r8, 256 			; actual future limit will be 512
	jae	.err2

	mov	rbp, gThreadIDs_lock
	mov	rsi, gThreadIDs
	and	eax, [rbp]			; cache the cacheline with double mem access
	test	[rbp], ecx
	jmp	.0

.1:	call	resumeThreadSw
.0:	bt	dword [rbp], 0
	jc	.1
.2:	call	noThreadSw
	lock
	bts	dword [rbp], 0
	jc	.1

@@:
	mov	ecx, r8d
	mov	eax, r8d
	shr	ecx, 6
	and	eax, 63
	bts	[rsi + rcx*8], rax
	jc	.err				; jump if id is already in a free state
	; CF=0

	sfence
.exit:
	mov	dword [rbp], 0
	call	resumeThreadSw
@@:	pop	rsi rcx rax rbp
	ret
.err:	stc
	jmp	.exit
.err2:	stc
	jmp	@b

;===================================================================================================
;    noThreadSw
;===================================================================================================
; nested noThreadSw & resumeThreadSw are not allowed
; If you called noThreadSw and then called ANY function (without doing resumeThreadSw first) then
;    assume there will be nested noThreadSw

	align 4
noThreadSw:
	pushf
	or	word [lapicT_flags], 4
	popf
	ret

; TODO: keep track of time that was not counted because LapicT was not running
;	if we entered LapicT we start measurment there and restore in resumeThreadSw

;===================================================================================================
;   resumeThreadSw
;===================================================================================================
; 4byte mem access has been atomic for a while across single CPU. x86-64 do atomic non-aligned 4byte.
; Meaning, modifying/reading/both will not result in one portion of memory modified and the
;					    other is not in case an interrupt(irq) happens
;---------------------------------------------------------------------------------------------------
; nested noThreadSw & resumeThreadSw are not allowed
; If you called noThreadSw and then called ANY function (without doing resumeThreadSw first) then
;    assume there will be nested noThreadSw

	align 4
resumeThreadSw:
	pushf
	push	rax

	and	dword [lapicT_flags], not 4	; disable request to stop thread switch
	mov	rax, cr8			; serializing instr. (AND always executed before BT)
	bt	dword [lapicT_flags], 3
	jnc	@f

	; if bit 3 was set by lapicTimer then we won't enter the lapicT handler anymore unless
	; we trigger lapicT handler manually
	int	LAPICT_vector			; <<<<< don't need EOI <<<<<
@@:
	pop	rax
	popf
	ret

