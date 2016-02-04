
; Distributed under GPL v1 License
; All Rights Reserved.


;===================================================================================================
;
;===================================================================================================


	align 8
alloc_linAddr:
	ret



;===================================================================================================
; Function is meant to be used to allcocate ram for paging structures only
; That is separate 4kb pages to hold PML4s, PDPs, PDs and PTs.
;===================================================================================================
; input:  mem ptr where to save physical ram addrs, one 4kb page - one 8byte addr
;	  number of 8kb pages to allocate (?zeroed are always prefered)



; need separate ring0 stack for each thread
; all ring3 & ring0 drivers/apps with separate stack

; need separate "zero4kb" proc and not "rep stosq" as we might need to test ram for errors

	align 8
alloc4k_ram:
	push	rax rcx rsi rdi rbx rbp rdx
.stack=64
	mov	rdi, [rsp + .stack+8]		; RDI
.alloc:
	noThreadSw

	mov	eax, [pgRam4_size]
	cld
	cmp	dword [rsp + .stack], 0 	; number of 8byte addrs
	jle	.exit
	test	eax, eax
	jz	.16kb
	jmp	.exit

;---------------------------------------
.16kb:
	; check if 4kb host page present
	lea	rcx, [paging_ram]
	mov	rsi, 0xffff'fff0'0000'0000
	shr	rcx, 12
	or	rsi, rcx
	shl	rcx, 12
	test	dword [rsi*8], 1
	jnz	@f

	call	refill_pagingRam    ; nested threadSwitch	     ; in case no host page
	test	dword [rsi*8], 1
	jz	k64err
@@:
	mov	eax, [rcx]			; size
	xor	r8, r8				; =0 if dirty chunks
	cmp	dword [rcx+4], 0
	mov	esi, 1024
	mov	ebp, [rsp + .stack]
	setnz	r8b				; =1 if zeroed chunks
	test	eax, eax
	jz	.unmap_host

	sub	esi, eax
	sub	eax, ebp
	jnc	@f
	add	ebp, eax
	jz	k64err
	xor	eax, eax
@@:

       ; TODO: attempt to resume thread switch, if we do - we start over entire 'alloc4k_ram'


	shl	r8, 63
	mov	[rcx],	 eax			; eax = # of chunks left in the host page
	sub	[rsp + .stack], ebp		; ebp = # of chunks allocated during this loop
	jc	k64err

	lea	rcx, [rcx + rsi*4]		; where from we read 4b indexes

	mov	esi, 4096
	push	rbp
	shr	ebp, 2
	jz	.single
@@:
	mov	eax, [rcx]
	add	rcx, 4
	shl	rax, 14
	or	rax, r8
	stosq
	add	rax, rsi
	stosq
	add	rax, rsi
	stosq
	add	rax, rsi
	stosq
	sub	ebp, 1
	jnz	@b
.single:
	pop	rbp
	and	ebp, 3
	jz	.done

	mov	eax, [rcx]

	shl	rax, 14
	or	rax, r8
@@:
	stosq
	add	rax, rsi
	sub	ebp, 1
	jnz	@b
.done:
	cmp	dword [rsp + .stack], 0
	jz	.exit

	resumeThreadSw
	jmp	.alloc
.exit:
	resumeThreadSw
	pop	rdx rbp rbx rdi rsi rcx rax
	ret

;---------------------------------------------------------------------------------------------------
.unmap_host:
	lea	rcx, [paging_ram]
	mov	rsi, 0xffff'fff0'0000'0000
	shr	rcx, 12
	or	rsi, rcx
	shl	rcx, 12
	mov	qword [rsi*8], 0
	invlpg	[rcx]
	resumeThreadSw
	jmp	.alloc

	jmp	k64err

;===================================================================================================
;   refill_pagingRam   - host page with 16KB indexes (R8 physical) will be mapped at "paging_ram"
;===================================================================================================
; return: r8 - physical mem ptr to host page with 16KB indexes

	align 8
refill_pagingRam:
	push	rax rdi rcx rsi rbp

	; try taking one host 4KB page away from #PF first
.local_alloc:
	noThreadSw

	mov	rax, [PF_pages]
	movzx	edi, al 	; dil = bitmask
	movzx	ebp, ah
	cmp	ah, 7
	ja	@f
	bts	edi, ebp	; exclude 4kb that in use by #PF at the moment
@@:	not	edi
	mov	r8, rax
	bsf	ebp, edi
	cmp	ebp, 7
	ja	.global_alloc	; no pages mapped, we'll look into 'page in use by #PF' later

	shl	ebp, 12
	mov	rdi, rax
	shl	r8, 16
	lea	rsi, [PF_ram + rbp]
	mov	ecx, [rsi]
	mov	r9d, [rsi + 4]
	shr	rdi, 48
	shr	rbp, 12
	shr	r8, 16

	add	ecx, r9d
	jc	k64err
	cmp	ecx, 0x3fc
	ja	k64err
	sub	di, cx
	jc	k64err

	shl	rdi, 48
	bts	r8, rbp
	or	rdi, r8 	; final 8byte that go into "PF_pages"

	; get the phys addr before setting bit in PF_pages bitmask
	mov	r8, 0xffff'fff0'0000'0000
	shr	rsi, 12
	or	r8, rsi
	mov	r8, [r8*8]

	cmpxchg [PF_pages], rdi
	jz	@f
	resumeThreadSw
	jmp	.local_alloc
@@:
	; map the 4kb page
	lea	rsi, [paging_ram]
	mov	r9, 0xffff'fff0'0000'0000
	ror	rsi, 12
	or	r8, 3
	or	r9, rsi
	rol	rsi, 12
	mov	[r9*8], r8
	invlpg	[rsi]

	jmp	.exit

;---------------------------------------------------------------------------------------------------
	align 4
.global_alloc:

	; get a lock
	mov	edi, memPtr
@@:	resumeThreadSw
	bt	dword [rdi + 12], 0
	jc	@b
	noThreadSw
	lock
	bts	dword [rdi + 12], 0
	jc	@b

	mov	r8, [rdi]		; ptr
	lea	rsi, [paging_ram]
	shr	r8, 12
	jz	.noGlobRam
	shl	r8, 12

	; map the 4kb page
	mov	r13, 0xffff'fff0'0000'0000
	ror	rsi, 12
	or	r8, 3
	or	r13, rsi
	rol	rsi, 12
	mov	[r13*8], r8
	invlpg	[rsi]

	mov	ecx, [rsi]		; size
	mov	r9d, [rsi + 4]		; zeroed/dirty
	mov	r12, [rsi + 8]		; ptr to next 4kb
	cmp	ecx, 0x3fc
	ja	k64err

	; update info and release the lock
	mov	[rdi], r12
	sub	[rdi + 8], ecx
	jc	k64err
	sfence
	btr	dword [rdi + 12], 0
	jmp	.exit

;---------------------------------------------------------------------------------------------------
	align 4
.mem_alloc:
	; - try 4kb that is currently in use by #PF
	; - ask other CPUs
	jmp	k64err

;---------------------------------------------------------------------------------------------------
	align 4
.exit:
	shr	r8, 12
	shl	r8, 12

	resumeThreadSw
	pop	rbp rsi rcx rdi rax
	ret

.noGlobRam:
	cmp	dword [rdi + 8], 0
	jnz	k64err
	btr	dword [rdi + 12], 0
	jmp	.mem_alloc


;===================================================================================================
;   update_PF_ram   -  map 4KB pages (with 16KB RAM indexes) for #PF handler to use
;===================================================================================================

	align 8
update_PF_ram:
	push	rax rcx rsi rdi
	noThreadSw		    ; TODO: quene made of functions

	; TODO: we need to unmap old pages first (PF handler does set bits but doesn't unmap)

	mov	rax, [PF_pages]
	lea	rsi, [PF_ram]
	bsf	rcx, rax		; find page that doesn't have RAM anymore (page still mapped)
	jz	.no_update
	cmp	ecx, 7
	ja	.no_update
	mov	r14d, ecx

@@:	; if empty page found then alloc RAM from global pool
	mov	edi, memPtr
	lock
	bts	dword [rdi + 12], 0	; set global lock bit first, then can put cpuID bit
	jc	@b

	mov	r12, [rdi]		; ptr

	; map 4kb page into PF_ram according to the bit in ecx
	shl	ecx, 12
	add	rsi, rcx
	mov	r13, 0xffff'fff0'0000'0000
	ror	rsi, 12
	or	r12, 3
	or	r13, rsi
	rol	rsi, 12
	mov	[r13*8], r12
	invlpg	[rsi]

	mov	ecx, [rsi]		; size
	mov	r9d, [rsi + 4]		; zeroed/dirty
	mov	r12, [rsi + 8]		; ptr to next 4kb
	cmp	ecx, 0x3fc
	ja	k64err

	; release the lock
	mov	[rdi], r12
	sub	[rdi + 8], ecx
	jc	k64err
	sfence
	mov	rax, [PF_pages] 	; earlier set bit will remain set, other info updated
	btr	dword [rdi + 12], 0

	; update info for PF handler
@@:	mov	esi, eax
	mov	rdi, rax
	btr	esi, r14d
	jnc	k64err
	shr	rdi, 48
	movzx	r9d, r9w
	add	di, cx
	jc	k64err
	shl	rdi, 48
	shl	r9, 32
	or	rdi, rsi
	or	rdi, r9
	cmpxchg [PF_pages], rdi
	jnz	@b

	clc
.exit:
	resumeThreadSw
	pop	rdi rsi rcx rax
	ret

.no_update:
	stc
	jmp	.exit

;===================================================================================================
; Fragment RAM, about 64MB per function call
;===================================================================================================
; mem is chopped from higher addrs as lower regions of RAM are more useful for device drivers
; Function must run on one CPU at a time.
; Usage of already fragmented memory is not restricted by other CPUs.
;
; return: CF=1 when all RAM fragmented (keep calling this function until you get CF=1 on return)

	align 8
fragmentRAM:

.sz=16
	; alloc host 16KB where we save indexes of the remaining 16KB chunks
	; 1020 indexes per 4KB times 4 results in 63.75MB of RAM
.alloc_host:

	mov	r12d, [qword memMap_cnt2 + rmData]
	mov	esi, memMap + rmData
	imul	r12d, .sz
	add	esi, r12d
@@:
	sub	rsi, .sz
	sub	r12d, .sz
	jc	.completed
	cmp	byte [rsi+7], 1
	jnz	@b

	mov	eax, [rsi]
	mov	ebx, [rsi+8]
	test	ebx, ebx
	jz	@b

	sub	ebx, 1
	mov	[rsi+8], ebx
	add	eax, ebx
	jc	k64err

	shl	rax, 14
	mov	rcx, rax		; rcx - physical addr

	mov	r8, fragMem + 3
	mov	r9, rax
	mov	r12d, 16384
	call	mapToKnownPT

	;-------------------------- fill in 4KB -----

	mov	r10, rcx		; r10
	mov	rdi, r8
	xor	r14, r14
.4kb:
	mov	r12d, [qword memMap_cnt2 + rmData]
	mov	esi, memMap + rmData
	imul	r12d, .sz
	add	esi, r12d
@@:
	sub	rsi, .sz
	sub	r12d, .sz
	jc	.completed
	cmp	byte [rsi+7], 1
	jnz	@b
	mov	eax, [rsi]
	mov	ebx, [rsi+8]
	test	ebx, ebx
	jz	@b




	add	rcx, 4096		; rcx - physical addr
	mov	ebp, 1020
	sub	ebx, 1020
	mov	[rsi+8], ebx
	jnc	@f
	lea	ebp, [ebx + 1020]
	xor	ebx, ebx
	mov	[rsi+8], ebx
@@:
	mov	dword [rdi], ebp	; size
	mov	dword [rdi+4], 0	; =0 if dirty chunks
	mov	qword [rdi+8], rcx	; current phys 4kb -> next phys 4kb

	add	eax, ebx
	mov	r13, rdi		; r13 - ptr to last processed 4kb
	add	rdi, 1023*4
	lea	eax, [rax + rbp - 1]

	add	r14d, ebp		; r14 - mem size

	std
	shr	ebp, 1
	jnc	.fill_4kb
	stosd
	jz	@f
	sub	eax, 1
.fill_4kb:
	stosd
	sub	eax, 1
	stosd
	sub	eax, 1
	sub	ebp, 1
	jnz	.fill_4kb
@@:
	lea	rdi, [r13 + 4096]
	test	rdi, 16383
	jz	@f
	jmp	.4kb
@@:



	; get a lock
	mov	edi, memPtr
@@:	bt	dword [rdi + 12], 0
	jc	@b
	lock
	bts	dword [rdi + 12], 0
	jc	@b

; OR and "js" size flag

	mov	rax, [rdi]		; ptr
	mov	edx, [rdi + 8]		; total mem
	mov	[r13 + 8], rax		; end of this 16kb(or less) chunk -> old ptr
	add	r14d, edx		; new size + old size
	jc	k64err
	mov	[rdi], r10
	mov	[rdi + 8], r14d

	; release the lock
	sfence
	btr	dword [rdi + 12], 0
	jnc	k64err

	clc
.exit:
	ret

.completed:
	mov	dword [qword memMap_cnt2 + rmData], 0
	stc
	jmp	.exit

;===================================================================================================
; Map mem into present chain of PML4->PDP->PD->PT. Source addr+size must not cross 2MB alignment.
; No sanity checking is performed whatsoever!
;===================================================================================================
; input:  r8  - dest addr (must be 4KB aligned, low 12bits used as flags)
;	  r9  - src addr (no alignment requirement)
;	  r12 - src size in bytes
;
; return: r8 points to the 1st byte of the mapped memory
;	  none of the other registers modified

	align 8
mapToKnownPT:
	push	r12 rbx rcx rax r9
	cmp	r12, 0x200000
	jg	k64err

	add	r12, r9
	mov	ebx, r9d
	mov	ecx, r8d
	ror	r8, 12
	shr	r9, 12
	mov	rax, 0xffff'fff0'0000'0000
	and	ebx, 4095
	and	ecx, 4095
	shl	r9, 12
	or	rax, r8
	shl	r8, 12
	or	rcx, r9
	sub	r12, r9
	shl	rax, 3

	push	r8
@@:
	mov	[rax], rcx
	add	rax, 8
	add	rcx, 4096
	invlpg	[r8]
	add	r8, 4096
	sub	r12, 4096
	jg	@b

	pop	r8
	add	r8, rbx

	pop	r9 rax rcx rbx r12
	ret

