
; Distributed under GPL v1 License
; All Rights Reserved.



;===================================================================================================
; Fragment RAM, about 64MB per function call
;===================================================================================================

  align 8
fragmentRAM:


	ret

;===================================================================================================
; Map mem into present chain of PML4->PDP->PD->PT. Source addr+size must not cross 2MB alignment.
; No sanity checking is performed whatsoever!
;===================================================================================================
; input:  r8  - dest addr (must be 4KB aligned, low 12bits used as flags)
;	  r9  - src addr
;	  r12 - src size in bytes
;
; return: r8 points to the 1st byte of the mapped memory
;	  r9, r12 are not changed
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
	add	rax, 16
	add	rcx, 4096
	invlpg	[r8]
	add	r8, 4096
	sub	r12, 4096
	jg	@b

	pop	r8
	add	r8, rbx

	pop	r9 rax rcx rbx r12
	ret

