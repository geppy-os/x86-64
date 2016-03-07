
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
; called only once

	align 8
thread_create_system:

	mov	dword [timers_local + TIMERS.1stFree], -1	; init timer list

	mov	word [lapicT_currTID], 0

	mov	rdi, cr3
	mov	[lapicT_kPML4], rdi


	xor	eax, eax
	mov	word [threads + THREAD.gTID], ax
	mov	word [threads + THREAD.time2run], 65535

	not	rax
	;mov	 rax, 0x0001'0002'0003'0004
	mov	[lapicT_pri0], rax
	mov	word [lapicT_pri0], 0




								; 14  12  10  e  c  a  8  4  2	0
	mov	dword [lapicT_priQuene], 0x87184'00		; 10'00'01'11'00'01'10'00'01'00b shl 8
								; 2  0	1  3  0  1  2  0  1   0


	mov	byte [qword 0], 0x30

	;

	ret


;===================================================================================================
; input: r8   = flags (PG_USER, ..)
;	 r9d  = size in 16KB units (min 1MB, max 1GB), must account for thread header
;		thread space can be extended later by loading libraries & allocating mem
;---------------------------------------------------------------------------------------------------
; starting addr + size can't overlap with the stack, obviously
; "alloc_linAddr" function will take care of any overlapping regions since it doesn't allow to alloc
; already allocated regions considering correct flags provided while calling "alloc_linAddr"


	align 8
thread_create:
	push	rax rcx rsi rdi rbp
	mov	r13, r8

	mov	rax, 0x200000000
	cmp	r9, 0x10000		; max 1GB size
	ja	.err
	cmp	r9, 64			; min 1MB size
	jb	.err

	call	thread_allocID
	jc	.err
	push	r8
	reg	r8, 100a

	imul	r8, 0x10000 * 512	; r8 *= 512GB in 16KB units
	lea	r12, [r8 + 0x10000*512] ; stack is at the end of 512GB
	push	r8 r9
	reg	r9, 100a
	reg	r12, 100a

.vars = 24
.allowed_flags = PG_USER

	mov	r8, [rsp + 8]
	reg	r8, 100a

	mov	rdi, [feature_XD]			; RDI
	sub	r12, 128
	and	r13, .allowed_flags
	mov	rbp, r8 				;	RBP
	mov	rcx, r12				; RCX
	mov	rsi, r13				;	RSI

	; alloc space for control block and code
	mov	rax, not 127
	add	r9, 127 				; round size up to 2MB
	mov	r12, rsi
	and	r9, rax
	or	r12, PG_P + PG_RW + PG_ALLOC		; PG_RW needed to copy code, will be removed
	mov	[rsp], r9
	call	alloc_linAddr
	jc	k64err

	; alloc space for the stack
	mov	r12, rdi				; execute disable bit
	mov	r8, rcx
	or	r12, rsi
	mov	r9d, 0x200000/16384
	or	r12, PG_P + PG_RW + PG_ALLOC + PG_MORE_STACK
	call	alloc_linAddr
	jc	k64err

	shl	rbp, 14
	mov	r8, [rbp]				; let #PF alloc physical RAM

	; get physical addresses of new PML4 & PDP
	lea	rcx, [rbp + 4096*2]
	lea	rax, [rbp + 4096*3]
	mov	r8, 0xffff'fff0'0000'0000
	mov	r9, 0xffff'fff0'0000'0000
	ror	rcx, 12
	ror	rax, 12
	or	r8, rcx
	or	r9, rax
	mov	r8, [r8*8]				; r8
	mov	r9, [r9*8]				; r9

	; prefetch PML4
	lea	rcx, [rbp + 4096*2]
	mov	rax, 0x1fff'ffff'ffff'fe00 shl 3
	mov	r12d, 4096/128
@@:	test	[rax], ecx
	test	[rax + 32], eax
	test	[rax + 64], ecx
	test	[rax + 96], eax
	add	rax, 128
	sub	r12d, 1
	jnz	@b











	call	noThreadSw

	; clone PML4
	lea	rcx, [rbp + 4096*2]
	mov	rax, 0x1fff'ffff'ffff'fe00 shl 3
	mov	r12d, 4096/128
@@:	movdqa	xmm0, [rax]
	movdqa	xmm1, [rax + 16]
	movdqa	xmm2, [rax + 32]
	movdqa	xmm3, [rax + 48]
	movdqa	xmm4, [rax + 64]
	movdqa	xmm5, [rax + 80]
	movdqa	xmm6, [rax + 96]
	movdqa	xmm7, [rax + 112]
	movdqa	[rcx], xmm0
	movdqa	[rcx + 16], xmm1
	movdqa	[rcx + 32], xmm2
	movdqa	[rcx + 48], xmm3
	movdqa	[rcx + 64], xmm4
	movdqa	[rcx + 80], xmm5
	movdqa	[rcx + 96], xmm6
	movdqa	[rcx + 112], xmm7
	add	rax, 128
	add	rcx, 128
	sub	r12d, 1
	jnz	@b

	; switch to new PML4
	;	  (next time when we switch BACK to SYS thread we'll get all changes automatically)
	mov	cr3, r8
	lea	rsi, [@f]
	push	8 rsi
	retf
@@:
	call	resumeThreadSw



	; then we delete entries from current PML4
	; and switch to new PML4 and thus we'll change running thread


	;  we need noThreadSw to alloc new thread id


.ok:	clc
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
;    thread_allocID
;===================================================================================================
; return: r8 - thread id
;	  all other registers preserved

	align 8
thread_allocID:
	push	rbp rax rcx rdi

	mov	rbp, gThreadIDs_lock
	jmp	.0
.1:	call	resumeThreadSw
.0:	bt	dword [rbp], 0
	jc	.1
.2:	call	noThreadSw
	lock
	bts	dword [rbp], 0
	jc	.1



	mov	rcx, gThreadIDs

	mov	rax, [rcx]
	mov	rdi, [rcx + 8]
	bsf	r8, rax
	jnz	.3
	bsf	r8, rdi
	jnz	.4

	mov	rax, [rcx + 16]
	mov	rdi, [rcx + 24]
	bsf	r8, rax
	jnz	.5
	bsf	r8, rdi
	jz	.err



	btr	rdi, r8
	mov	[rcx + 24], rdi
	add	r8, 3*64
	jmp	@f
.3:
	btr	rax, r8
	mov	[rcx], rax
	jmp	@f
.4:
	btr	rdi, r8
	mov	[rcx + 8], rdi
	add	r8, 1*64
	jmp	@f
.5:
	btr	rax, r8
	mov	[rcx + 16], rax
	add	r8, 2*64
@@:



	sfence
	clc
.exit:
	mov	dword [rbp], 0
	call	resumeThreadSw
	pop	rdi rcx rax rbp
	ret
.err:
	stc
	jmp	.exit

;===================================================================================================
;    thread_releaseID
;===================================================================================================


	align 8
thread_releaseID:
	ret


;===================================================================================================
; copy

thread_load:
	ret


;===================================================================================================

thread_destroy:
	ret


; get file size, use thread_create to allocate space, use thread_load to load the file


; will be a list of files that need to be loaded at startup
; we'll put locks on them all and use "file_info" to get file size
; then use thread_create and thread_load

; then library_load wil be used to extend thread space or create new thread for new executable


; xsave:
; execution of XSETBV with ECX=0 causes EDX:EAX written to XCR0 (intel Vol1 13.3)
;					EAX[0] must be 1 (intel Vol2 XSETBV instruction)
; need per thread stack for alloc4k_ram


;===================================================================================================

	align 8
sleep:
	ret


;===================================================================================================

	align 8
clone_pml4:
	ret

;===================================================================================================
; can not use CLI instruction until resumeThreadSw is called

	align 8
noThreadSw:
	pushf
	or	word [lapicT_flags], 4
	popf
	ret

; maybe reserve R14 to save time that was not counted because LApicT was not running
; if we entered LapicT we start measurment there and restore in in resumeThreadSw

;===================================================================================================
; can not use CLI instruction until resumeThreadSw is called

	align 8
resumeThreadSw:
	pushf
	and	dword [lapicT_flags], not 4	; disable request to stop thread switch
	test	dword [lapicT_flags], 8 	; precache the cacheline (2 mem acceses)
	mfence					; wait before next memory operation
	push	rax rcx
	mov	eax, 2				; disable low priority ints for a short time
	mov	cr8, rax
	mov	ecx, [lapicT_flags]
	xor	eax, eax			; re-enable ALL (default) ints
	mov	cr8, rax

	; if this flag is set by lapicT then we won't enter the lapicT handler anymore unless
	; we trigger lapicT handler manually
	test	ecx, 8
	jz	@f
	int	0x20				; <<<<< don't need EOI <<<<< (bit3 at lapicT_flags)
@@:
	pop	rcx rax
	popf
	ret
