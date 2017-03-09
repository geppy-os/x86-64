
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	 align 8
int_PF:
	push	r8 r15 rax rcx rsi rdi rbx
	mov	rax, [rsp + 7*8]
	mov	[rsp + 7*8], rbp
	sub	rsp, 24

	mov	r15, [sp_PF_r15]
	mov	rbp, cr2
	shl	r15, 16

	; in case somebody made a mess writing this handler (2nd #PF while executing this handler)
	cmp	byte [sp_PF_2nd], 0x5a
	jz	k64err.pf_2nd_PF
	mov	byte [sp_PF_2nd], 0x5a


	mov	ecx, [sp_PF_pages]
	mov	ebx, [sp_PF_pages + 4]


	; All paging tables are always mapped
	; They are never unmapped even if PT entries are not beeing used for a long time

	; if addr belongs to paging hierarchy (top bits are 1s 0xffff... ) then kernel panic
	bt	rbp, 63
	jc	k64err.pf_paging_addr

	ror	rbp, 39
	mov	rsi, 0xffff'ffff'ffff'fe00

	or	rsi, rbp
	mov	rdi, [rsi*8]			; get PDP address from PML4 entry
	mov	rsi, 0xffff'ffff'fffc'0000
	rol	rbp, 9			   ; 1
	xor	edi, 1				; invert Present flag
	test	edi, 1000'0001b 		; PS(pageSize) must be 0, P(present) must be 1
	jnz	k64err.pf_invalid_PML4e

	or	rsi, rbp
	mov	rdi, [rsi*8]			; get PD address from PDP entry
	mov	rsi, 0xffff'ffff'f800'0000
	rol	rbp, 9			   ; 2
	xor	edi, 1
	test	edi, 1000'0001b
	jnz	k64err.pf_invalid_PDPe

	or	rsi, rbp
	mov	rdi, [rsi*8]			; get PT address from PD entry
	mov	rsi, 0xffff'fff0'0000'0000
	rol	rbp, 9			   ; 3
	xor	edi, 1
	test	edi, 1000'0001b
	jnz	k64err.pf_invalid_PDe

	or	rsi, rbp			; RSI = PT entry (points to 4 KB)
	shr	rsi, 2				;	align to a multiple of 4
	shl	rsi, 2				;	we operate in 16KB chunks

	mov	rdi, [rsi*8]
	test	edi, 1				; Must be zero. Issue (=1) happens on Bochs-2.68 emulator
	jnz	k64err.P_0			;    but error code reports correct "page not present"
	test	edi, PG_ALLOC
	jz	k64err.pf_notAllocated

	; check if we have valid page (1byte value) selected at "PF_pages+1"
	mov	edi, ecx
	cmp	ch, 8
	jb	@f

	; if host page is not selected then do so (happens rarely)
	not	rdi
	bsf	rax, rdi
	cmp	eax, 7
	ja	k64err.pf_noHostPagesMapped
	mov	ch, al
	shl	eax, 12
	mov	edi, [PF_ram + rax]		; size
	mov	eax, [PF_ram + 4 + rax] 	; dirty/zeroed
	ror	ecx, 16
	cmp	edi, 0x3fc
	ja	k64err
	test	edi, edi
	jz	k64err
	mov	cx, di
	mov	bx, ax
	ror	ecx, 16
@@:
	movzx	eax, ch 			; page #
	ror	ecx, 16
	movzx	edi, cx 			; size
	shl	eax, 12
	neg	rdi
	lea	rax, [PF_ram + 4096 + rax]
	mov	edi, [rax + rdi*4]		; EDI = 16kb index

	ror	ebx, 16
	sub	cx, 1				; cached page size --
	jc	k64err
	sub	bx, 1				; total size --
	jc	k64err
	ror	ecx, 16
	ror	ebx, 16
	mov	[sp_PF_pages], ecx
	mov	[sp_PF_pages + 4], ebx

	shl	rdi, 14
	or	rdi, 3
	mov	[rsi*8], rdi
	add	rdi, 4096
	mov	[rsi*8 + 8], rdi
	add	rdi, 4096
	mov	[rsi*8 + 16], rdi
	add	rdi, 4096
	mov	[rsi*8 + 24], rdi

	shr	rbp, 2				; multiple of 4 entries
	shl	rbp, 2 + 12			; low 12 bits is offset within 4KB page
	invlpg	[rbp]
	invlpg	[rbp + 4096]
	invlpg	[rbp + 4096*2]
	invlpg	[rbp + 4096*3]

	; zero mapped 16kb
	test	bx, bx				; BL =0 if 4kb page dirty, !=0 if 4kb with zeroed chunks
	jnz	@f
	cld
	mov	rdi, rbp
	xor	eax, eax
	mov	ecx, 16384/8
	cld
	rep	stosq
@@:

	;TODO
	; need to switch to another page if cached page size reached zero
	;jmp	k64err

  ; look thru pages - if none mapped and global mapped ram size 0 then exit #PF into ring0 and alloc,map

.exit:
	mov	byte [sp_PF_2nd], 0x33
	add	rsp, 24
	pop	rbx rdi rsi rcx rax r15 r8 rbp
	iretq




