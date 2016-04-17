
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8b  =0 if ISA, =1 if PCI
;	 r9   - device id

	align 8
dev_install:
	push	rax rcx rdi

	and	r8d, 0xff
	call	dev_find
	mov	rax, r8
	jc	k64err


	; we have to figure how to distribute interrupts (in this function or somewhere else)

	mov	ecx, [rax + 8]
	cmp	cl, 1
	jb	.ISA
	jz	.PCI
	jmp	.err
.PCI:
	jmp	.get_id
.ISA:
	mov	r8d, isaDevs



.get_id:
	; calculate 2byte unique ID for the device driver
	call	rand_tsc
	mov	r12d, inst_devs_cnt
	mov	r14d, inst_devs
	mov	r13d, 1
	xadd	[r12], r13d			; get 2byte array index
	shl	r13d, 16
	or	r8, r13 			; merge unique id with array index (4byte unique id)

	mov	eax, [rax + 4]
	lea	r9, [LMode]
	add	rax, r9

	; save unique id & device info address
	shr	r13d, 16
	imul	r13d, 12
	mov	[r14 + r13], r8d
	mov	[r14 + r13 + 4], rax

	; call init function
	push	r8
	call	rax

	clc
.exit:
	pop	rdi rcx rax
	ret
.err:
	stc
	jmp	.exit

; ISA IDE disk tells us which interrupt triggered (int handler needs input data)
; and calls int_remove on unused interrupt vector

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; return: r8 = pointer to device info

	align 8
dev_find:
	push	rax rcx rsi rdi rbp rbx
	cld

	lea	rsi, [dev_vendors]
	mov	r10, rsi
	and	r8d, 0xff

	lodsq
	cmp	eax, 16
	jb	.err
	lea	ebp, [eax - 8]
	mov	edi, eax
	shr	rax, 32
	mov	r12d, eax
	xor	ecx, ecx
	xor	eax, eax
@@:	add	ecx, eax
	sub	r8d, 1
	jc	@f
	lodsd
	sub	ebp, 4
	jnz	@b
	jmp	.err			; can't find correct "entry type"
@@:
	lodsd				; EAX = number of vendor entries
	lea	rdi, [rcx*4 + rdi]	;	at EDI offset
	add	rdi, r10		; += base address
	add	r10, r12
	mov	r12d, ecx		; how many entries skipped
	mov	r13d, eax		; number of entries to be parsed
	mov	ecx, eax
	mov	eax, r9d
	repne	scasd			; return: ecx = # of entries left to be parsed
	cmp	[rdi - 4], eax
	jnz	.err			; no vendor name

	not	ecx
	add	ecx, r13d		; ecx = # of entries already parsed
	add	ecx, r12d		; += # of skipped entries
	mov	esi, [r10 + rcx*4]
	add	rsi, r10

	lodsd
	ror	r9, 32
@@:	sub	eax, 1
	jc	.err			; no devices for specefied vendor
	cmp	[rsi], r9d
	jz	@f
	add	rsi, 12
	jmp	@b
@@:	mov	r8, rsi
	clc
.exit:
	pop	rbx rbp rdi rsi rcx rax
	ret
.err:
	stc
	jmp	.exit

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8  = 4byte unique id given to device driver during initialization
;	 r9  = 8byte interrupt handler address
;	 r12 = ??? someting MSI related (per MSI handler data)
;---------------------------------------------------------------------------------------------------
; TODO: can call this function multiple times if MSI-X supported with different r9 (need int_remove)

	align 8
int_install:
	pushf
	push	rax rcx rsi
	cli

	mov	ecx, r8d
	shr	r8d, 16
	mov	r14, inst_devs
	cmp	[qword inst_devs_cnt], r8d
	jbe	.err
	imul	r8d, 12
	cmp	[r14 + r8], ecx
	jnz	.err
	mov	r14, [r14 + r8 + 4]

	;reg	 r8, 82f
	;reg	 rcx, 42f
	;reg	 r14, 102f


.exit:
	pop	rsi rcx rax
	popf
	ret
.err:
	stc
	jmp	.exit


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8[7:0]    - vector in idt
;	 r8[11:8]   - IST
;	 r9	    - handler mem address
;	 r12[7:0]   - ioapic input
;	 r12[9:8]   - ioapic id
;	 r12[11:10]   = 0
;	 r12[13:12]   = ioapic trigger : polarity
;	 r12[15:14]   = 0

	align 8
int_install2:
	pushf
	push	rax rcx rsi
	cli

	mov	eax, r12d
	movzx	ecx, r12b

	call	idt_setIrq

	xor	r12, r12
	and	r8d, 255
	bt	eax, 13
	setc	r12b
	mov	rsi, ioapic
	shl	r12d, 2
	bt	eax, 12
	movzx	eax, ah
	adc	r12d, 0
	and	eax, 3
	shl	r12d, 13
	shl	eax, 12
	or	r8, r12
	add	rsi, rax

	lea	ecx, [rcx*2 + 0x11]
	mov	dword [rsi], ecx		; high dword
	mov	dword [rsi + 16], 0
	sub	ecx, 1
	mov	dword [rsi], ecx		; low dword
	mov	dword [rsi + 16], r8d

	pop	rsi rcx rax
	popf
	ret

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8[7:0]   - vector in idt
;	 r8[11:8]  - IST
;	 r9	   - handler mem address
; return: input r8 not modified

	align 8
idt_setIrq:
	push	rbx rcx r8 rax rdx

	lea	rbx, [idt]
	mov	eax, r8d
	and	r8d, 255
	xchg	rbx, r9
	and	eax, 0xf00
	mov	rcx, rbx
	mov	ebx, ebx
	shr	rcx, 32
	ror	ebx, 16
	mov	r12, 0x8e00'0008'0000
	ror	rbx, 16
	shl	rax, 24
	or	rbx, r12
	shl	r8d, 4
	or	rbx, rax

	mov	rax, [r9 + r8]
	mov	rdx, [r9 + r8 + 8]

	cmpxchg16b [r9 + r8]
	jnz	k64err

	pop	rdx rax r8 rcx rbx
	ret

