
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



;===================================================================================================
; input: r8d	   = kernel device id
;	 r9	   = 4byte interrupt handler offset/addr (relative to the beginning of the thread)

	align 4
syscall_intInstal:

	;TODO: need to copy dev handler from thread space to kernel space
	;      or not ?

	xor	r12, r12
	jmp	int_install

;===================================================================================================
; input: r8  - timeout in microseconds (up to 1 second); if =0 then wait for event only
;	       must be zero if putting other thread to sleep

	align 4
syscall_threadSleep:
	mov	r9d, [lapicT_currTID]
	xchg	r8, r9
	jmp	thread_sleep


;===================================================================================================
;////////////  SYSCALL handler (replacement if SYSCALL instruction unavailable)  ///////////////////
;===================================================================================================
; mainly to be used by ring0 code that wants to go thru system call wrapper
;---------------------------------------------------------------------------------------------------
;  input: r15		     function number & additional flags
;	  r8,r9,r12,r13,r14  function input parameters
; return: rbx,rdx,r10	     =0
;	  rcx,r11	     = undefined
;	  r8,r9,r12,r13,r14  =0 unless used for return values
;			       its the job of the called function to zero them - not syscall handler
;
; preserved on return: rax,rsi,rdi,r15,rbp,rsp, all SSE & AVX regs
;---------------------------------------------------------------------------------------------------

	align 4
syscall_k:

; normally,
; user stuff is saved by CPU on input:	R11 = RFLAGS
;					RCX = next RIP (where to return)
;					RSP is left as it is, after user code (must not trust it)
;	we do it manually here
	pushfq					; using user(main) stack
	pop	r11
	mov	rcx, [rsp]
;--------------------------------------


	mov	r10, r15
	mov	rdx, rcx

	mov	r15, 0x400000

	shr	rcx, 39 			; rcx = kernel cpu id
	shl	rcx, 39
	mov	[rcx + 32768-8], rsp
	mov	[rcx + 32768-16], rsi
	mov	[rcx + 32768-24], rdi
	mov	[rcx + 32768-32], r10		; r15
	mov	[rcx + 32768-40], rbp
	mov	[rcx + 32768-48], rax
	mov	[rcx + 32768-56], r11		; flags
	mov	[rcx + 32768-64], rdx		; rip

	lea	rsp, [rcx + 32768-128]		; expect around 12KB of stack here

   reg 0, 100e
   reg r10, 20e

	;----------------------------------------
	lea	rdi, [sys_calls]
	movzx	eax, r10w
	cmp	eax, sys_calls.max
	ja	k64err.syscall_invalidNum

	mov	eax, [rdi + rax*4]
	add	rax, LMode2
	call	rax
	jc	k64err

	mov	r11d, 0
	adc	r11d, r11d			; returned CF set/cleared

	mov	rcx, [rsp + 64]
	shr	rcx, 39
	shl	rcx, 39
	mov	rsp, [rcx + 32768-8]
	mov	rsi, [rcx + 32768-16]
	mov	rdi, [rcx + 32768-24]
	mov	r15, [rcx + 32768-32]
	mov	rbp, [rcx + 32768-40]
	mov	rax, [rcx + 32768-48]
	or	r11, [rcx + 32768-56]		; old RFLAGS + CF from syscall
	mov	rcx, [rcx + 32768-64]		; RIP

	xor	edx, edx
	xor	ebx, ebx
	xor	r10, r10

;----------------------------------------
	push	r11				; using user(main) stack
	popfq
	ret
