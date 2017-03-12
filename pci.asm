
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



;---------------------------------------------------------------------------------------------------
; we prefere info from PCI config space directly if available
; with ISA devs - there is no other way but to use ACPI
; to connect PCI devs to IOAPIC we also need ACPI (DSDT & SSDTs)
; but we'll use info from PCI config space first, wherever we can
;---------------------------------------------------------------------------------------------------



;===================================================================================================
;   pci_figureMMIO  -  determine if mem mapped io is supported	 ///////////////////////////////////
;===================================================================================================

pci_figureMMIO:

	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	bts	qword [r14 + 8192 + functions], FN_PCI_FIGUREMMIO


	movzx	r8d, byte [qword max_pci_bus + rmData]

	mov	esi, pciDevs + rmData			; rsi
	mov	edx, [qword pciDevs_cnt + rmData]	; edx
	sub	esi, 16
	mov	edi, [qword devInfo_cnt]
	mov	r9, [qword devInfo]			; r9
	mov	ebp, edi				; ebp
	imul	edi, devInfo_sz
	lea	r9, [r9 + rdi - devInfo_sz]
	cmp	ebp, 16
	jl	k64err.notEnoughDevs


.nextDev:
	add	r9, devInfo_sz
	add	ebp, 1
	add	esi, 16
	sub	edx, 1
	jc	.done

	; bus/dev/func (test MMIO here, and save new info into eax)
	mov	eax, [rsi]


	call	rand_tsc
	shl	r8d, 16
	or	r8d, ebp
	bts	r8d, 15

	movzx	edi, word [rsi + 4]
	movzx	ecx, word [rsi + 6]
	shl	rdi, 32
	or	rdi, rcx
	mov	ecx, [rsi + 8]
	mov	eax, [rsi]

	mov	dword [r9], r8d 		 ; kernel dev id
	mov	dword [r9 + 4], eax		 ; bus/dev/func
	mov	word  [r9 + 14], -1		 ; no thread assigned
	mov	dword [r9 + 24], ecx		 ; 3byte classcode
	mov	qword [r9 + 16], rdi		 ; vendor & device

	push	rdx
	cli
	mov	eax, [rsi]
	add	eax, 0x3c
	mov	dx, 0xcf8
	out	dx, eax
	mov	dx, 0xcfc
	in	eax, dx 			; AH: bits[3:0] = PCI A/B/C/D
	shr	eax, 8
	or	eax, 0x30			; bit5: classcode present flag, bit4: id present
	sti
	mov	[r9 + 9], al
	pop	rdx

	jmp	.nextDev

.done:
	sub	ebp, 1
	mov	[qword devInfo_cnt], ebp


macro asd{
	mov	rsi, [qword devInfo]
	reg	rsi, 101a
	mov	ecx, [qword devInfo_cnt]
@@:	reg	[rsi], 80a
	reg	[rsi + 4], 40b
	reg	[rsi + 9], 20b
	reg	[rsi + 12], 20b
	reg	[rsi + 13], 20b
	add	rsi, devInfo_sz
	sub	ecx, 1
	jnz	@b
}

	pushf
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	btr	qword [r14 + 8192 + functions], FN_PCI_FIGUREMMIO
	popf
	ret

;===================================================================================================
;   Get BAR info from PCI config space using regular IO
;===================================================================================================

; and maybe determine if mmio supported here

pci_getBARs:
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	bts	qword [r14 + 8192 + functions], FN_PCI_GETBARS



	mov	r8, pciDevs + rmData - 16

	align 8
.next_dev:
	add	r8, 16
	sub	ebp, 1
	jc	.exit
	movzx	eax, byte [r8 + 12+2]		; get "Header Type"
	cmp	byte [r8 + 8+3], 6		; skip all bridges
	jz	.next_dev
	mov	esi, [r8]
	and	eax, 0x7f			; remove "mult-function device" bit
	jnz	.next_dev			; skip non Type0 layout which only applies to bridges


	jmp	.next_dev


;---------------------------------------------------------------------------------------------------
.exit:

	pushf
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	btr	qword [r14 + 8192 + functions], FN_PCI_GETBARS
	popf
	ret
























