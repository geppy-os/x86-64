
; Distributed under GPL v1 License
; All Rights Reserved.


; TODO: if addr belongs to paging hierachy (top bits are 1s 0xffff... ) then kernel panic

	 align 8
int_PF:
	push	r8 r15 rax rcx rsi rdi rbx
	mov	rax, [rsp + 7*8]
	mov	[rsp + 7*8], rbp
	sub	rsp, 24

	mov	rbp, cr2
	mov	r15, [sp_PF_r15]

	; in case somebody made a mess wring this handler (2nd #PF while executing this handler)
	cmp	byte [sp_PF_2nd], 0x5a
	jz	.2nd_PF
	mov	byte [sp_PF_2nd], 0x5a

	;mov	 dword [qword 32], (0x4f shl 24) + (0x4f  shl 8) + '_' + ('P' shl 16)
	;mov	 dword [qword 36], (0x4f shl 24) + (0x4f  shl 8) + 'F' + ('_' shl 16)
	;mov	 esi, [qword reg32.cursor]
	;mov	 dword [qword reg32.cursor], 42
	;lea	 rax, [rsp+112]
	;reg	 rax, 104f
	;reg	 rbp, 104f
	;mov	 [qword reg32.cursor], esi

	mov	ecx, [sp_PF_pages]
	mov	ebx, [sp_PF_pages + 4]
	shl	r15, 16

	; All paging tables are always mapped
	; They are never unmapped even if PT entries are not beeing used for a long time

	ror	rbp, 39
	mov	rsi, 0xffff'ffff'ffff'fe00

	or	rsi, rbp
	mov	rdi, [rsi*8]			; get PDP address from PML4 entry
	mov	rsi, 0xffff'ffff'fffc'0000
	rol	rbp, 9			   ; 1
	xor	edi, 1				; invert Present flag
	test	edi, 1000'0001b 		; PS(pageSize) must be 0, P(present) must be 1
	jnz	.invalid_PML4e

	or	rsi, rbp
	mov	rdi, [rsi*8]			; get PD address from PDP entry
	mov	rsi, 0xffff'ffff'f800'0000
	rol	rbp, 9			   ; 2
	xor	edi, 1
	test	edi, 1000'0001b
	jnz	.invalid_PDPe

	or	rsi, rbp
	mov	rdi, [rsi*8]			; get PT address from PD entry
	mov	rsi, 0xffff'fff0'0000'0000
	rol	rbp, 9			   ; 3
	xor	edi, 1
	test	edi, 1000'0001b
	jnz	.invalid_PDe

	or	rsi, rbp			; RSI = PT entry (points to 4 KB)
	shr	rsi, 2				;	align to a multiple of 4
	shl	rsi, 2				;	we operate in 16KB chunks
	mov	rdi, [rsi*8]
	test	edi, 1
	jnz	k64err
	test	edi, PG_ALLOC
	jz	.notAllocated

	; check if we have valid page (1byte value) selected at "PF_pages+1"
	mov	edi, ecx
	cmp	ch, 8
	jb	@f

	; if host page is not selected then do so (happens rarely)
	not	rdi
	bsf	rax, rdi
	cmp	eax, 7
	ja	.noHostPagesMapped
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
	;reg	 rdi, 69a

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
	test	bx, bx
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
;SS
;RSP
;RFLAGS
;CS
;RIP
;Error Code

; it can be that no pages are mapped but size is not zero at "PF_pages"
; if this case 'alloc_ram' is allocating ram from PF pool


; #PF happened while #PF handler was executing
.2nd_PF:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + '2' + ('n' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'd' + ('!' shl 16)
	reg	rbp, 10cf
	jmp	$

; PG_ALLOC bit is not set
.notAllocated:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'A' + ('L' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'O' + ('C' shl 16)
	jmp	$

; bitmask in "PF_pages" is empty (all 8 bits set)
.noHostPagesMapped:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + '-' + ('H' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 's' + ('T' shl 16)
	jmp	$

; no PageDirectoryPointer (512GB chunk)
.invalid_PML4e:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('M' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'L' + ('e' shl 16)
	jmp	$

; no PageDirectory (1GB chunk)
.invalid_PDPe:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('D' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('e' shl 16)
	jmp	$

; no PageTable (2MB chunk)
.invalid_PDe:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('D' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'e' + (' ' shl 16)
	jmp	$

