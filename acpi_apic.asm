
; Distributed under GPL v1 License
; All Rights Reserved.


;===================================================================================================
; get IOAPICs & LAPICs
; setup IOPIC IDs
; setup ISA IRQs -> IOAPIC redirection
;===================================================================================================

acpi_parse_MADT:

	; maybe keep this isa data structure on a stack for the duration of this function

	; setup default ISA -> IOAPIC mapping (will be overwritten by parsing MADT)
	mov	rsi, isaDevs
	xor	eax, eax
	mov	ecx, 16
@@:	mov	[rsi], eax		; store default ACPI GlobIntNumber
	mov	byte [rsi + 12], 0	; default polarity=0, trigger=0, entry not present =0
	add	eax, 1
	add	rsi, 20
	sub	ecx, 1
	jnz	@b


	; map MADT

	mov	r9d, [qword acpi_apic + rmData]
	mov	r12d, [qword acpi_apic_len + rmData]
	cmp	r12d, 0x100000
	jge	.exit
	cmp	r12, 48
	jl	.exit

	mov	r8, acpiTbl + 3
	call	mapToKnownPT

	; parse MADT

	add	r12, r8 		; end of MADT,	R12
	add	r8, 44
	xor	edx, edx
	mov	r9, r8
	mov	r10, largestLapicID

	mov	ebx, ioapic_gin 	; where GlobIntNumbers go
	xor	ecx, ecx		; number of IOAPICs * 4bytes
	mov	edi, ioapic		; where IOAPICs are mapped
	not	rcx
	mov	[rbx], rcx
	mov	[rbx+8], rcx
	xor	ecx, ecx

.1st_pass:
	add	r8, rdx
	cmp	r8, r12
	jae	.APICs_done
	mov	eax, [r8]
	movzx	edx, ah

	;reg	 rax, 406

	cmp	ax, 0x0800
	jz	.lapic
	cmp	ax, 0x0c01
	jz	.ioapic
	jmp	.1st_pass
;----------------------------
.lapic:
	mov	ebp, [r10]
	test	dword [r8 + 4], 1
	jz	.1st_pass

	reg	rax, 405

	shr	eax, 16
	movzx	esi, al
	shr	eax, 8
	reg	rax, 205
	reg	rsi, 205



	cmp	ebp, eax
	jae	.1st_pass

	mov	[r10], ebp
	jmp	.1st_pass

;----------------------------
.ioapic:
	reg	rax, 406

	mov	ebp, [r8 + 4]	; addr
	mov	esi, [r8 + 8]	; starting GIN (range to be retrieved from IOAPIC itself)
	cmp	ecx, 16
	jae	.1st_pass
	test	ebp, 4095
	jnz	.1st_pass
	test	ebp, ebp
	jz	.1st_pass

	; map IOAPIC right away
	mov	rax, 0xffff'fff0'0000'0000
	ror	rdi, 12
	or	rbp, 10011b
	or	rax, rdi
	rol	rdi, 12
	mov	[rax*8], rbp
	invlpg	[rdi]

	mov	[rbx + rcx], esi
	add	rdi, 4096
	add	ecx, 4
	jmp	.1st_pass

.APICs_done:

	; IOAPIC ID needs to be larger than largest LAPIC ID
	; Intel MPSpecs v1.4 chapter "3.6.6 APIC Identification"
	;----------------------------------------------------

	; create mask of unused IDs
	mov	ecx, [r10]
	xor	ebp, ebp
	not	ebp
	cmp	ecx, 14
	jae	k64err
	add	ecx, 1
	shl	ebp, cl 	; EBP: bit set - ID free, bit cleared - ID taken
	and	ebp, 0xffff

	mov	ebx, ioapic_inputCnt-1
	mov	esi, ioapic-4096
	mov	edi, ioapic_gin-4

.ioapic_setID:
	add	rsi, 4096
	add	rdi, 4
	add	rbx, 1
	cmp	rsi, ioapic+4096*3
	ja	.ioapic_done
	cmp	dword [rdi], -1
	jz	.ioapic_setID

	mov	dword [rsi], 0
	mov	eax, [rsi + 16]
	mov	dword [rsi], 1
	mov	ecx, [rsi + 16]
	mov	r8d, eax
	shr	eax, 24
	shr	ecx, 16
	and	eax, 15 		; id	       eax
	and	ecx, 255		; input cnt-1	ecx
	add	ecx, 1
	btr	ebp, eax
	jnc	@f
	mov	[rbx], cl
	jmp	.ioapic_setID
@@:
	bsf	eax, ebp
	jz	.ioapic_setID
	btr	ebp, eax
	shl	eax, 24
	and	r8d, 0xf0ff'ffff
	or	r8d, eax
	mov	dword [rsi], 0
	mov	dword [rsi + 16], r8d
	mov	[rbx], cl
	jmp	.ioapic_setID

.ioapic_done:
	; at this point we must use 'ioapic_inputCnt' to determine if ioapic exist/valid
	; 'ioapic_gin' must no longer be used fo this purpose

	cmp	dword [qword ioapic_inputCnt], 0
	jz	.exit

;----------------------------
	mov	r8, r9
	mov	r9, isaDevs
	xor	edx, edx

.2nd_pass:
	add	r8, rdx
	cmp	r8, r12
	jae	.2nd_pass_done
	mov	eax, [r8]
	movzx	edx, ah

	cmp	ax, 0x0a02
	jz	.isa_override
	jmp	.2nd_pass

.isa_override:
	reg	rax, 403
	mov	ecx, [r8 + 4]		; GIN (GlobIntNum)
	shr	eax, 24 		; al = isa irq
	reg	rcx, 404
	reg	rax, 405
	imul	edi, eax, 20
	mov	[r9 + rdi], ecx

	movzx	eax, byte [r8 + 8]
	and	eax, 1111b
	shl	eax, 6			; al[7:6] = polarity, ah[1:0] = trigger
	cmp	al, 10'000000b
	jz	.2nd_pass
	btr	eax, 6
	cmp	ah, 10b
	jz	.2nd_pass
	shr	ah, 1
	shr	eax, 3
	mov	byte [r9 + rdi + 12], al
	jmp	.2nd_pass

;------------------------------------------
.nmi_lapic:
	jmp	.2nd_pass

;------------------------------------------
.nmi_ioapic:
	jmp	.2nd_pass


.2nd_pass_done:


	; convert GlobIntNum into IOAPIC kernel_id and IOAPIC input
	;-----------------------------------------------------------

	mov	esi, isaDevs
	mov	ebp, 16
.IRQ_fix:
	mov	ecx, [rsi]
	xor	edi, edi
	not	edi
@@:
	add	edi, 1
	cmp	edi, 4
	jae	.next_irq		; 'present' flag should already be cleared
	mov	eax, [qword ioapic_gin + rdi*4]
	movzx	ebx, byte [qword ioapic_inputCnt + rdi]
	cmp	eax, ecx
	ja	@b			; next ioapic if starting GIN > required
	add	ebx, eax
	cmp	ecx, ebx
	jae	@b			; next ioapic if required GIN outside this ioapic range

	sub	ecx, eax		; ecx = ioapic input, edi = ioapic kernel id
	cmp	ecx, 255
	ja	.next_irq

	or	edi, 0x80		; add present flags - bit 7
	mov	[rsi + 11], cl
	or	[rsi + 12], dil

.next_irq:
	add	rsi, 20
	sub	ebp, 1
	jnz	.IRQ_fix

	; PIC spurious IRQs can't be connected to anything
	mov	esi, isaDevs
	xor	eax, eax
	mov	[rsi + 7*20], eax
	mov	[rsi + 7*20 + 12], eax
	mov	[rsi + 15*20], eax
	mov	[rsi + 15*20 + 12], eax

.exit:
	ret






