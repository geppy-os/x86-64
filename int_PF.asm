
; Distributed under GPL v1 License
; All Rights Reserved.


macro  sdf{
	mov	rcx, 0xfffffff'ff'ff'ff'000	; PML4 table (low 12 bits = 512 entries * 8bytes)
	mov	rdx, 0xfffffff'ff'fe'00'000	; PDP #0 (mapped into PML4e #0)
						; (low 12bits = 512 entries in PDP #0 * 8b)
	mov	rbp, 0xfffffff'ff'fe'01'000	; PDP #1 (mapped into PML4e #1)
	mov	rdi, 0xfffffff'fc'00'00'000	; PD #0 (mapped into PDP #0)
	mov	r11, 0xffffff8'00'00'00'000	; PT #0 (mapped into PD #0)

	mov	rax, [rcx]	; addr of PDP #0
	mov	rbx, [rdx]	; addr of PD #0 (mapped into PDPe #0)
	mov	rsi, [rdi]	; addr of PT #0 (mapped into PDe #0)
	mov	r10, [rdi+8]	; addr of PT #1 (mapped into PDe #1)
	mov	r12, [r11]
	mov	r13, [r11+8]
	mov	r14, [r11+16]

	reg	rax, 101f
	reg	rbx, 101f
	reg	rsi, 101f
	reg	r10, 101f
	reg	r12, 104f
	reg	r13, 104f
	reg	r14, 104f

	   pml4e     pdpe	pde	    pte
       111111111 ' 111111111 ' 111111111 ' 111111111 '	12bits
}




  align 8
int_PF:
	push	r8 r15 rax rcx rsi rdi rbx rbp
	mov	rcx, cr2

	mov	dword [qword 32], (0x4f shl 24) + (0x4f  shl 8) + '_' + ('P' shl 16)
	mov	dword [qword 36], (0x4f shl 24) + (0x4f  shl 8) + 'F' + ('_' shl 16)
	mov	esi, [qword reg32.cursor]
	mov	dword [qword reg32.cursor], 42
	mov	rax, rsp
	reg	rax, 104f
	reg	rcx, 104f
	mov	[qword reg32.cursor], esi


	ror	rcx, 39
	mov	rax, 0xffff'ffff'ffff'fe00
	or	rax, rcx
	mov	rdi, [rax*8]			; get PDP address from PML4 entry
	mov	rax, 0xffff'ffff'fffc'0000
	rol	rcx, 9
	test	edi, 1
	jz	.noPML4e

	reg	rdi, 1005

	or	rax, rcx
	mov	rdi, [rax*8]			; get PD address from PDP entry
	mov	rax, 0xffff'ffff'f800'0000
	rol	rcx, 9
	test	edi, 1
	jz	.noPDPe

	reg	rdi, 1006

	or	rax, rcx
	mov	rdi, [rax*8]			; get PT address from PD entry
	test	edi, 1
	jz	.noPDe

	reg	rdi, 1007

@@:
cli
hlt
jmp @b




	iretq

.noPML4e:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('M' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'L' + ('e' shl 16)
	jmp	$
.noPDPe:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('D' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('e' shl 16)
	jmp	$
.noPDe:
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('D' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'e' + (' ' shl 16)
	jmp	$

