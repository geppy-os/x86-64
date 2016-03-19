
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
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
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

pci_getBARs:

	; waiting for a proper malloc function
	mov	rdi, 0x1400000/16384
	mov	r9, 0x200000/16384
	mov	r8, rdi
	shl	rdi, 14
	mov	r12d, PG_P + PG_RW + PG_ALLOC
	call	alloc_linAddr
	jc	k64err.allocLinAddr		; need realloc without freeing already allocated mem

	mov	rcx, pciDevs + rmData - 16
	mov	ebp, [qword pciDevs_cnt + rmData]
	reg	rbp, 80a
.next_dev:
	add	rcx, 16
	sub	ebp, 1
	jc	.exit

	mov	eax, [rcx]
	reg	rax, 80a
	jmp	.next_dev



.exit:
	ret
























