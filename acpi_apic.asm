
;---------------------------------------------------------------------------------------------------
; Distributed under GPL v1 License
; All Rights Reserved.
;---------------------------------------------------------------------------------------------------

acpi_parse_MADT:

	; setup default ISA -> IOAPIC mapping (will be overwritten by parsing MADT)


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
	test	dword [r8 + 4], 1
	jz	.1st_pass
	reg	rax, 406


	jmp	.1st_pass

;----------------------------
.ioapic:
	reg	rax, 406

	mov	ebp, [r8 + 4]	; addr
	mov	esi, [r8 + 8]	; GIN
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
;====================================================


;LAPIC ignores the trigger mode unless programmed as 'fixed'


;For all normal interrupts and IPIs
;(but not for NMI, SMI, INIT or spurious interrupts) you need to send an EOI to the local APIC


; for entries bellow:
;--------------------


	mov	r8, r9
	xor	edx, edx


.2nd_pass:
	add	r8, rdx
	cmp	r8, r12
	jae	.exit
	mov	eax, [r8]
	movzx	edx, ah
	cmp	ax, 0x0a02
	jz	.isa_override
	jmp	.2nd_pass

.isa_override:
	reg	rax, 403
	jmp	.2nd_pass





.exit:
	ret