
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



;===================================================================================================
;    mem_setFlags  -  set paging flags for individual 4KB pages, lin addr must already be allocated
;===================================================================================================
; input: r8  = linear address in bytes, must be 4KB aligned
;	 r9  = size in bytes, must be a multiple of 4KB
;	 r12 = paging flags, all flags zeroed and replaced with r12
;
;--------------------------------------------------------------------------------------------------
; Size at R9 is limited only by available x64 linear space but function operates on 2MB at a time.
; If possible use alloc_linAddr to alloc 2MB and then use mem_setFlags to change flags within 2MB.
; Until function returns, one portion of memory may use one set of flags, another - different flags

	align 8
mem_setFlags:
	push	rax rcx rsi rdi rbp
;	 mov	 byte [errFL + FUNC_MEMSETFLAGS], 1	; per thread all of these
;	 add	 byte [errF + FUNC_MEMSETFLAGS], 1

	mov	rdi, 4095
	test	r9, rdi
	jnz	.err
	test	r8, rdi
	jnz	.err
	mov	rdi, 0x7fff'ffff'ffff
	shr	r9, 12				; size -> 4KB units
	jz	.err
	cmp	r8, rdi 			; less than 128TB staring addr
	ja	.err

.process_2MB:
	ror	r8, 39
	mov	rsi, 0xffff'ffff'ffff'fe00

	or	rsi, r8
	mov	rdi, [rsi*8]			; get PDP address from PML4 entry
	mov	rsi, 0xffff'ffff'fffc'0000
	rol	r8, 9			   ; 1
	xor	edi, 1				; invert Present flag
	test	edi, 1000'0001b 		; PS(pageSize) must be 0, P(present) must be 1
	jnz	.err				; invalid PML4 entry

	or	rsi, r8
	mov	rdi, [rsi*8]			; get PD address from PDP entry
	mov	rsi, 0xffff'ffff'f800'0000
	rol	r8, 9			   ; 2
	xor	edi, 1
	test	edi, 1000'0001b
	jnz	.err				; invalid PDP entry

	or	rsi, r8
	mov	rdi, [rsi*8]			; get PT address from PD entry
	xor	edi, 1
	test	edi, 1000'0001b
	jnz	.err				; invalid PD entry

	mov	rsi, 0xffff'fff0'0000'0000
	rol	r8, 9			   ; 3
	or	rsi, r8 			; RSI = PT entry (points to 4 KB)
	mov	edi, esi
	mov	ecx, esi
	or	edi, 0x1ff
	and	ecx, 0x1ff
	and	edi, 0x1ff
	sub	edi, ecx			; number of PT entries - 1
	add	edi, 1
	rol	r8, 12			   ; 4	  total 39bits
	cmp	rdi, r9
	cmova	rdi, r9
	sub	r9, rdi 			; global page counter -= local



	mov	rax, not 0x7fff'ffff'f000
	mov	rcx, 0x7fff'ffff'f000
	and	r12, rax
	mov	rbp, r8
@@:
	mov	rax, [rsi*8]
	test	rax, PG_ALLOC			; TODO: separate loops for validate, write & invlpg
	jz	k64err
	and	rax, rcx
	or	rax, r12
	mov	[rsi*8], rax
	invlpg	[rbp]
	add	rbp, 4096
	add	rsi, 1
	sub	edi, 1
	jnz	@b


	; switch to next 2MB (at r8)
	or	r8, 0x1fffff
	test	r9, r9
	jz	.ok
	add	r8, 1
	jmp	.process_2MB

.ok:
	;and	 dword [errF], not FUNC_MEMSETFLAGS
	clc

.exit:	pop	rbp rdi rsi rcx rax
	ret
.err:
	stc
	jmp	.exit


;===================================================================================================
;    alloc_linAddr  -  allocate linear addrs were #PF will map physical RAM later
;===================================================================================================
; input: r8  = linear address in 16KB units (addr, after converted to bytes must be 2MB aligned)
;	 r9  = size in 16KB units (max 0x10000), must be a multiple of 2MB when converted to bytes
;	 r12 = flags
;
; return: CF=1 if failed, otherwise CF=0
;
;--------------------------------------------------------------------------------------------------
; None of the linear memory in range of "addr + size" must be mapped prior to calling this function.
; Lin addr + size can't cross 1GB alignment. 1GB = 0x40000000 bytes = 0x10000 16KB units
;								    128TB = 0x2'0000'0000 16KB units
; All allocations must be 2MB aligned (starting address) bacause same 4KB PT(same mem usage) is used
; for all within 2MB. This greatly reduces bloated code and logic in this function.
;
; There is no additional physical RAM used if allocation are 2MB aligned versus 4KB aligned alloc.
; This is how it's setup by Intel/AMD. And the linear addrs space is quite huge on x64.


	align 8
alloc_linAddr:
	push	rax rcx rdi rsi rbp rbx

	bsr	rax, r8
	cmp	r9, 0x10000
	ja	.err
	cmp	eax, 32 		; starting lin addr must be bellow 128TB
	ja	.err
	test	r9, r9
	jz	.err
	test	r9, 127 		; size must be 2MB aligned
	jnz	.err
	test	r8, 127 		; addr must be 2MB aligned
	jnz	.err

	mov	r13, r8 		; starting 16kb (1st 4kb out of 4)		  rdi r13 -a
	mov	r14, r9 		; size						      r14 s

	; check if starting addr + size cross 1GB or not

	lea	r9, [r9 + r8 - 1]	; -= 16KB ! ! !

	mov	rsi, r9 		; ending 16kb (1st 4kb out of 4)		      rsi -a
	shr	r9, 16
	shr	r8, 16
	cmp	r9, r8
	jnz	.err			; jump if ending addr crosses 1GB

	mov	r8, 2			; =2 if we need PDP & PD, =1 if PD only, =0 if none
	shl	r13, 14 		; convert to bytes from 16kb units
	shl	rsi, 14
	mov	rdi, r13
	mov	rbx, r12		; rbx - flags

	; PDP(512GB) & PD(1GB) are shared among starting $ ending addrs (making this func simpler)

	ror	r13, 39
	mov	rax, 0xffff'ffff'ffff'fe00
	or	rax, r13
	test	dword [rax*8], 1	; do we have PML4e present -> PDP ?
	jz	.verify_PDes		; jump if no

	sub	r8d, 1

	rol	r13, 9
	mov	rax, 0xffff'ffff'fffc'0000
	or	rax, r13
	test	dword [rax*8], 1	; do we have PDPe present -> PD ?
	jz	.verify_PDes		; jump if no

	sub	r8d, 1

	; none of the PDes must be in use since start addr is 2MB aligned and size is 2MB aligned
.verify_PDes:
	;reg	 r8, 32f
	ror	rdi, 21 		; starting PDe, will be starting PTe later
	ror	rsi, 21 		; ending PDe		 ending PTe
	mov	eax, edi
	mov	ebp, esi
	and	eax, 0x1ff
	and	ebp, 0x1ff
	sub	ebp, eax
	add	ebp, 1			; number of PDes, min 1 (each PDe points to a PT)     EBP
	test	r8, r8
	jnz	.alloc_ram		; no need to verify PD entries since PD is not present

	; verify PD entries now, to avoid freeing RAM later

	mov	r13, 0xffff'ffff'f800'0000
	mov	eax, ebp
	mov	r12, r13
	or	r13, rdi
	or	r12, rsi

	shr	eax, 1
	jnc	@f
	test	dword [r13*8], 1
	jnz	.err
	add	r13, 1
	test	eax, eax
	jz	.PDes_verified
@@:
	test	dword [r13*8], 1
	jnz	.err
	test	dword [r13*8 + 8], 1
	jnz	.err
	add	r13, 2
	sub	eax, 1
	jnz	@b

.PDes_verified:
	sub	r13, 1
	cmp	r13, r12
	jnz	k64err

.alloc_ram:
	lea	eax, [r8 + rbp]
	;reg	 rax, 32f
	shl	eax, 3
	sub	rsp, rax		; RSP modified
	shr	eax, 3
	mov	r8, rsp

	push	r8 rax
	call	alloc4kb_ram
	add	rsp, 16

	; map PDP and PD if needed

	mov	r13, rdi
	lea	rcx, [rsp + rax*8]	; for additional validation purposes, later on	     RCX
	ror	r13, 18

	sub	eax, ebp		; restore original r8 (whenether PDP or PD tables present)
	;reg	 rax, 32f
	jz	.map_PTs
	cmp	eax, 2
	jb	.map_PD
.map_PDP:
	;reg	 rax, 012e
	mov	r8, [rsp]
	mov	r9,  0xffff'ffff'ffff'fe00
	mov	r12, 0x1fff'ffff'fffc'0000 shl 3
	call	.map_page
	add	rsp, 8			; remove "mov r8,[rsp]" value
.map_PD:
	;reg	 rax, 012e
	rol	r13, 9
	mov	r8, [rsp]
	mov	r9,  0xffff'ffff'fffc'0000
	mov	r12, 0x1fff'ffff'f800'0000 shl 3
	call	.map_page
	add	rsp, 8			; remove "mov r8,[rsp]" value

.map_PTs:
	;reg	 rbp, 32f
	mov	r10, rdi
	mov	r11, rbp		; ??
	mov	r12, 0x1fff'fff0'0000'0000 shl 3
@@:
	mov	eax, ebx
	mov	r8, [rsp]
	and	eax, PG_USER + PG_ALLOC 	; allowed user specified flags
	add	rsp, 8
	or	r8, rax
	mov	r9, 0xffff'ffff'f800'0000
	btr	r8, 63			; remove dirty/zeroed bit, we'll fill this page with values
	or	r9, rdi
	or	r8, PG_P + PG_RW
	mov	[r9*8], r8
	;reg	 r8, 105f
	shl	r9, 12			; entry #0 in the table (low 12bits are zero)
	or	r9, r12
	invlpg	[r9]
	add	rdi, 1
	sub	ebp, 1
	jnz	@b

.PTs_mapped:
	cmp	rsp, rcx
	jnz	k64err

	; allocate PT entries (PTes)
	; PG_ALLOC flag must be set for so that #PF can map physical RAM
	mov	rbp, r10
	mov	rdi, r10
	mov	rcx, rsi
	mov	r9, 0xffff'fff0'0000'0000
	rol	rdi, 9
	rol	rbp, 9
	rol	rcx, 9
	or	rdi, r9
	mov	r8, PG_USER + PG_RW + PG_ALLOC + PG_MORE_STACK + PG_XD
	and	ebp, 0x3ffff		; 18bits (PDes & PTes)
	and	ecx, 0x3ffff
	and	rbx, r8
	shl	rdi, 3
	sub	ecx, ebp		; number of entries (generally, many hundreds)
	mov	rax, rbx
	;reg	 rax, 106f
	add	ecx,  4 		; += 16KB ! ! !
	rep	stosq			; stosQ, fastest filling method on x64 unless AVX involved

.ok:
	clc
.exit:	pop	rbx rbp rsi rdi rcx rax
	ret
.err:	stc
	jmp	.exit

;--------------------------------------------------------------------------
; return: CF=1 if page didn't pass memory test, CF=0 if page is OK to use

	align 8
.map_page:
	push	rcx

	mov	ecx, ebx
	and	ecx, PG_USER + PG_ALLOC 	; allowed user specified flags
	or	r8, rcx

	btr	r8, 63
	setc	cl
	or	r8, PG_P + PG_RW
	or	r9, r13
	mov	[r9*8], r8		; map table
	shl	r9, 12			; entry #0 in the table (low 12bits are zero)
	or	r9, r12
	invlpg	[r9]

	;reg	 r8, 104f

	test	cl, cl
	jnz	@f
	mov	r8, r9
	call	mem4kb_zero	; TODO: best map with cache disable, test, remap, and then zero
				;    What if one bad page is found ???
				;    Easiest is to thow all the pages out and start over
@@:
	clc
	pop	rcx
	ret


;===================================================================================================
;   alloc4kb_ram
;===================================================================================================
; input:  mem ptr where to save physical ram addrs, one 4kb page - one 8byte addr
;	  number of 8kb pages to allocate (TODO: dirty pages are always prefered)
;---------------------------------------------------------------------------------------------------
; Function is meant to be used to allocate ram for paging structures only
; That is separate 4kb pages to hold PML4s, PDPs, PDs and PTs.

	align 8
alloc4kb_ram:
	push	rax rcx rsi rdi rbx rbp rdx
.stack=64
	mov	rdi, [rsp + .stack+8]		; RDI
.alloc:
	call	noThreadSw

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

	call	resumeThreadSw
	jmp	.alloc
.exit:
	call	resumeThreadSw
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
	call	resumeThreadSw
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
	call	noThreadSw

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
	call	resumeThreadSw
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
@@:	call	resumeThreadSw
	bt	dword [rdi + 12], 0
	jc	@b
	call	noThreadSw
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

	call	resumeThreadSw
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
	call	noThreadSw		    ; TODO: quene made of functions

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
	jc	@b			; TODO: if we can't get lock - resumeThreadSw

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
	call	resumeThreadSw
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

;===================================================================================================
; input:  r8 = linear pointer to 4KB
; return: mem zeroed and all registers(including input) are preserved

	align 8
mem4kb_zero:
	push	rdi rax rcx

	;whenever mem is tested or not is determined by global policy
	;call	 mem4kb_test

	cld
	mov	rdi, r8
	mov	ecx, 4096/8
	xor	eax, eax
	rep	stosq			; stosQ is faster than SSE loop
	pop	rcx rax rdi
ret




