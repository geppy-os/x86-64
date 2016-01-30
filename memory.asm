
; Distributed under GPL v1 License
; All Rights Reserved.


;===================================================================================================

  align 8
alloc_linAddr:
	ret

;===================================================================================================

  align 8
update_PF_ram:
	push	rax rcx rsi rdi

	; TODO: we need to umap old pages first (PF handler does set bits but doesn't unmap)

	mov	rax, [PF_pages]
	lea	rsi, [PF_ram]
	bsf	rcx, rax	; find page that doesn't have RAM anymore (page still mapped)
	cmp	ecx, 7
	ja	.exit
	mov	r14d, ecx

@@:	; if empty page found then alloc RAM from global pool
	mov	edi, memPtr
	lock
	bts	dword [rdi + 12], 0		; set global lock bit first, then can put cpuID bit
	jc	@b

	mov	r12, [rdi]			; ptr

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

	mov	ecx, [rsi]
	mov	r12, [rsi + 8]		; ptr to next 4kb
	add	ecx, [rsi + 4]		; zeroed mem + dirty mem
	jc	k64err
	cmp	ecx, 0x3fc
	ja	k64err

	; release the lock
	mov	[rdi], r12
	sub	[rdi + 8], ecx
	jc	k64err
	sfence
	mov	rax, [PF_pages]
	btr	dword [rdi + 12], 0

	; update info for PF handler
@@:	mov	rsi, rax
	mov	rdi, rax
	mov	r13, 0xffff'ffff'ffff
	btr	rsi, r14
	shr	rdi, 48
	and	rsi, r13
	add	edi, ecx
	jc	k64err
	shl	rdi, 48
	or	rdi, rsi
	cmpxchg [PF_pages], rdi
	jnz	@b
.exit:
	pop	rdi rsi rcx rax
	ret

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
	mov	dword [rdi], 0		; zeroed chunks
	mov	dword [rdi+4], ebp	; dirty chunks
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



	; TODO: change lock bellow

	mov	rdi, memPtr
	mov	rax, [rdi]		; ptr
	mov	rdx, [rdi + 8]		; total mem
@@:
	mov	[r13 + 8], rax		; end of this 16kb(or less) chunk -> old ptr
	lea	rcx, [rdx + r14]	; old size + new size
	mov	rbx, r10		; begining os processed 16kb
	lock
	cmpxchg16b [rdi]		; compare rdx:rax -> replace with rcx:rbx
	jnz	@b


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

