
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;   pci_figureMMIO  -  determine if mem mapped io is supported	 ///////////////////////////////////
;===================================================================================================

pci_figureMMIO:
	mov	esi, [qword acpi_mcfg + rmData]
	mov	ebp, [qword acpi_mcfg_len + rmData]
	test	esi, esi
	jz	.done
	test	ebp, ebp
	jz	.done

	;reg	 rsi, 80a
	;reg	 rbp, 80a

.done:
	ret

;===================================================================================================
;   Get BAR info from PCI config space using either regular IO or mem mapped IO. MMIO is faster.
;===================================================================================================

pci_getBARs:

;	 ; waiting for a proper malloc function
;	 mov	 rdi, 0x1400000/16384
;	 mov	 r9, 0x200000/16384
;	 mov	 r8, rdi
;	 shl	 rdi, 14
;	 mov	 r12d, PG_P + PG_RW + PG_ALLOC
;	 call	 alloc_linAddr
;	 jc	 k64err.allocLinAddr		 ; need realloc without freeing already allocated mem

	mov	r8, pciDevs + rmData - 16
	mov	ebp, [qword pciDevs_cnt + rmData]
	;reg	 rbp, 80a

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
	bt	esi, 31
	jnc	.mmio
;--------------------------------------------------------------------- using regular IO ------------

	jmp	.next_dev


;-------------------------------------------------------------------- using Mem Mapped IO-----------
	align 8
.mmio:

	jmp	.next_dev


;---------------------------------------------------------------------------------------------------
.exit:
	ret
























