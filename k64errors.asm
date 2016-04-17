
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;     error handling for the 64bit long mode	////////////////////////////////////////////////////
;===================================================================================================

	align 8
k64err:

.allocLinAddr:

.timerIn_manyLapTicks:
.timerIn_timerCntNot0:
.timerIn_timerCntNot0_1:
.timerIn_timerCntNot0_2:
.lapT_doubleINT:
.lapT_manyTicks:
.lapT_noThreads:
.lapT_timerCntNot0:
.lapicT_wakeUpAt_smaller:
	jmp	.unknown


.pf_2nd_PF:
	mov	dword [kernelPanic], 0
	jmp	@f
.pf_notAllocated:
	mov	dword [kernelPanic], 1
	jmp	@f
.pf_noHostPagesMapped:
	mov	dword [kernelPanic], 2
	jmp	@f
.pf_invalid_PML4e:
	mov	dword [kernelPanic], 3
	jmp	@f
.pf_invalid_PDPe:
	mov	dword [kernelPanic], 4
	jmp	@f
.pf_invalid_PDe:
	mov	dword [kernelPanic], 5
	jmp	@f
.pf_paging_addr:
	mov	dword [kernelPanic], 6
	jmp	@f
.pf:
	mov	dword [kernelPanic], 7
	jmp	@f
.unknown:
	mov	dword [kernelPanic], 8
	jmp	@f
.GP:
	mov	dword [kernelPanic], 9
	jmp	@f
.DF:
	mov	dword [kernelPanic], 10
	jmp	@f
.P_0:
	mov	dword [kernelPanic], 11
	jmp	@f

@@:
	;cli
	;mov	 eax, -1
	;mov	 cr8, rax
	lea	rsp, [interrupt_stack]
	sub	rsp, 128

	cmp	dword [qword vbeLfb_ptr + rmData], 0
	jz	.textMode

;---------------------------------------------------------------------------------------------------
.graphicsMode:

	mov	[reg64_2.cursor], 10

	mov	r8, cr2
	mov	r9, rsp
	mov	r12d, 16
	call	regToAsciiHex

	lea	r8, [rsp + 16]
	lea	rax, [text1]
	mov	word  [r8], 10
	mov	word  [r8 + 2], 70
	mov	word  [r8 + 4], 16
	mov	word  [r8 + 6], 0 ;font id
	mov	dword [r8 + 8], 0xff ;color
	mov	word  [r8 + 12], 0
	mov	qword [r8 + 14], rsp
	mov	r9, screen
	call	txtOut_noClip

	mov	edi, [kernelPanic]
	lea	rsi, [k64err_messages]
	movzx	edi, word [rsi + rdi*2]
	lea	rsi, [k64err_messages.0]
	add	rdi, rsi

	mov	rsi, rdi
	mov	ecx, k64err_messages_len
	xor	eax, eax
	repne	scasb
	sub	rdi, rsi
	mov	ecx, 65535
	cmp	rdi, rcx
	cmova	edi, ecx

	mov	r8, rsp
	lea	rax, [text1]
	mov	word  [r8], 140
	mov	word  [r8 + 2], 70
	mov	word  [r8 + 4], di
	mov	word  [r8 + 6], 0 ;font id
	mov	dword [r8 + 8], 0xff ;color
	mov	word  [r8 + 12], 0
	mov	qword [r8 + 14], rsi;rax ;text ptr
	mov	r9, screen
	call	txtOut_noClip

	cli
	jmp	$;.graphicsMode



;---------------------------------------------------------------------------------------------------
.panic:
	mov	rax, 'X 6 4 P '
	mov	[qword 120], rax
	mov	rax, 'A N I C '
	mov	[qword 128], rax
	jmp	.panic

;---------------------------------------------------------------------------------------------------
.textMode:
	lea	rax, [kernelPanic]
	mov	eax, [rax]
	cmp	eax, 1
	jb	.0
	jz	.1
	cmp	eax, 3
	jb	.2
	jz	.3
	cmp	eax, 5
	jb	.4
	jz	.5
	cmp	eax, 7
	jb	.6
	jz	.7
	cmp	eax, 9
	jb	.8
	jz	.9
	cmp	eax, 11
	jb	.10
	jz	.11
	jmp	.err

.0:	; #PF: happened while #PF handler was executing
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + '2' + ('n' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'd' + ('!' shl 16)
	reg	rbp, 10cf
	jmp	.err

.1:	; #PF: PG_ALLOC bit is not set
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'A' + ('L' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'O' + ('C' shl 16)
	jmp	.err

.2:	; #PF: bitmask in "PF_pages" is empty (all 8 bits set)
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + '-' + ('H' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 's' + ('T' shl 16)
	jmp	.err

.3:	; #PF: no PageDirectoryPointer (512GB chunk)
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('M' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'L' + ('e' shl 16)
	jmp	.err

.4:	; #PF: no PageDirectory (1GB chunk)
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('D' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('e' shl 16)
	jmp	.err

.5:	; #PF: no PageTable (2MB chunk)
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + 'P' + ('D' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + 'e' + (' ' shl 16)
	jmp	.err
.6:
.7:

.8:	; unknown kernel panic
	mov	dword [qword 22], (0x4f shl 24) + (0x4f  shl 8) + ' ' + ('?' shl 16)
	mov	dword [qword 26], (0x4f shl 24) + (0x4f  shl 8) + ' ' + (' ' shl 16)
	jmp	.err

.9:	; #GP
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('G' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'P' + ('_' shl 16)
	jmp	.err

.10:	; #DF
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('D' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'F' + ('_' shl 16)
	jmp	.err

.11:	; #PF, Present bit must be 0 in a PTe
	mov	dword [qword 22], (0xcf shl 24) + (0xcf  shl 8) + 'P' + ('F' shl 16)
	mov	dword [qword 26], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('0' shl 16)
	jmp	.err
.err:
	mov	esi, [qword reg32.cursor]
	mov	dword [qword reg32.cursor], 42
	mov	rbp, cr2
	reg	rbp, 104f
	mov	rbp, rsp
	reg	rbp, 104f
	mov	[qword reg32.cursor], esi

	cli
	jmp	$



;============================================================================ for debugging ========
reg64_2:
	pushfq
	push	rdx rbx rax rdi rsi rbp rcx
	mov	rcx, rsp
	sub	rsp, 128
	movdqu	[rsp], xmm0
	movdqu	[rsp + 16], xmm1
	movdqu	[rsp + 32], xmm2
	movdqu	[rsp + 48], xmm3
	movdqu	[rsp + 64], xmm4
	movdqu	[rsp + 80], xmm5
	movdqu	[rsp + 96], xmm6
	movdqu	[rsp + 112], xmm7
	push	rcx

	mov	r8, [rcx + 8*9]

	sub	rsp, 64
	mov	r9, rsp
	mov	r12d, 16
	call	regToAsciiHex

	mov	eax, [.cursor]
	add	[.cursor], 16*7+4

	lea	r8, [rsp + 16]
	mov	word  [r8], ax
	mov	word  [r8 + 2], 120
	mov	word  [r8 + 4], 16
	mov	word  [r8 + 6], 0 ;font id
	mov	dword [r8 + 8], 0xff ;color
	mov	word  [r8 + 12], 0
	mov	qword [r8 + 14], rsp
	mov	r9, screen
	call	txtOut_noClip

	add	rsp, 64

	movdqu	xmm0, [rsp + 8]
	movdqu	xmm1, [rsp + 16 + 8]
	movdqu	xmm2, [rsp + 32 + 8]
	movdqu	xmm3, [rsp + 48 + 8]
	movdqu	xmm4, [rsp + 64 + 8]
	movdqu	xmm5, [rsp + 80 + 8]
	movdqu	xmm6, [rsp + 96 + 8]
	movdqu	xmm7, [rsp + 112 + 8]
	pop	rcx
	mov	rsp, rcx
	pop	rcx rbp rsi rdi rax rbx rdx
	popfq
	ret 8

.cursor dd 10		   ; to be fixed: we write into the 2MB meant for kernel code

;============================================================================ for debugging ========
reg64:
	pushfq
	push	rdx rbx rax rdi
	cli

	mov	ebx, [rsp + 56]
	mov	edx, 16
	mov	ah, bl
	shr	ebx, 8
	cmp	ebx, edx
	cmova	ebx, edx
	lea	edi, [rbx*2 + 2]
	xadd	[qword reg32.cursor], edi
	mov	rdx, [rsp + 48]
	lea	edi, [edi + ebx*2 - 2]
	std
.loop:
	mov	al, dl
	and	al, 15
	cmp	al, 10
	jb	@f
	add	al, 7
@@:	add	al, 48
	stosw
	ror	rdx, 4
	dec	ebx
	jnz	.loop

	pop	rdi rax rbx rdx
	popfq
	ret 16
