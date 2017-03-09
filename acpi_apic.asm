
; Distributed under GPL v1 License
; All Rights Reserved.

;===================================================================================================
;///////  acpi_parse_MCFG   ////////////////////////////////////////////////////////////////////////
;===================================================================================================
; we currently supports only one entry in this table

acpi_parse_MCFG:

	mov	r9d, [qword acpi_mcfg + rmData]
	mov	r12d, [qword acpi_mcfg_len + rmData]
	cmp	r12d, 0x100000
	jae	.exit
	cmp	r12, 0x3c			; ensure at least one 16byte entry
	jb	.exit

	mov	r8, acpiTbl + 3
	call	mapToKnownPT
	cmp	dword [r8], 'MCFG'
	jnz	.exit
	cmp	r12d, [r8 + 4]
	jnz	.exit

	lea	r12, [r12 + r8 - 16]		; end of MCFG
	add	r8, 0x2c
.loop:
	mov	rax, [r8]			; addr
	reg	rax, 100a
	movzx	eax, word [r8 + 8]		; ? matches ACPI "_SEG" if not 0
	reg	rax, 40a
	movzx	eax, byte [r8 + 10]		; starting pci bus
	reg	rax, 20a
	movzx	eax, byte [r8 + 11]		; ending pci bus
	reg	rax, 20a

	; commented bellow to force one entry
	;add	 r8, 16
	;cmp	 r8, r12
	;jbe	 .loop


.exit:
	ret


;===================================================================================================
;///////  acpi_parse_FADT  .. or FACP?	 ///////////////////////////////////////////////////////////
;===================================================================================================

acpi_parse_FADT:

	mov	r9d, [qword acpi_facp + rmData]
	mov	r12d, [qword acpi_facp_len + rmData]
	cmp	r12d, 0x100000
	jge	.err
	cmp	r12, 48
	jl	.err

	mov	r8, acpiTbl + 3
	call	mapToKnownPT
	cmp	dword [r8], 'FACP'
	jnz	.err
	cmp	r12d, [r8 + 4]
	jnz	.err

	add	r12, r8 		; end of FADT


	; for now, we'll assume that we have PS2(kbd irq 1, mouse irq 12) & RTC (irq 8)
	; device driver can always tell - no, there is no device for me(driver)


	;or	 dword [qword k64_flags], FLAGS_PS2
	;or	 dword [qword k64_flags], FLAGS_RTC	    ;  'PNP' + ('0B00' shl 32)

	mov	rsi, [qword devInfo]
	movzx	edi, word [lapicT_currTID]

	; RTC
	mov	rax, 'PNP0B00' shl 8			; something that meant to be found
	or	byte [rsi + 8*devInfo_sz + 8], 0x01
	or	byte [rsi + 8*devInfo_sz + 9], 0x10	; has id at +16
	mov	[rsi + 8*devInfo_sz + 14], di		; assigned thread id
	mov	[rsi + 8*devInfo_sz + 16], rax		; PNP ID  for ISA device

	; PS2 kbd
	mov	rax, 'PNP0100' shl 8
	or	byte [rsi + 1*devInfo_sz + 8], 0x01
	or	byte [rsi + 1*devInfo_sz + 9], 0x10	; has id at +16
	mov	[rsi + 1*devInfo_sz + 14], di
	mov	[rsi + 1*devInfo_sz + 16], rax

	; PS2 mouse
	mov	rax, 'PNP0120' shl 8
	or	byte [rsi + 12*devInfo_sz + 8], 0x01
	or	byte [rsi + 12*devInfo_sz + 9], 0x10
	mov	[rsi + 12*devInfo_sz + 14], di
	mov	[rsi + 12*devInfo_sz + 16], rax



	clc
.exit:	ret
.err:	stc
	jmp	.exit

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; initialize "devInfo" array
; get IOAPICs & LAPICs
; setup IOPIC IDs
; setup ISA IRQs -> IOAPIC redirection
; setup "devInfo" array & related variables
;---------------------------------------------------------------------------------------------------

acpi_parse_MADT:

	mov	rax, 0x10'00000/16384
	mov	r8, rax
	shl	rax, 14
	mov	r9d, 0x200000/16384
	mov	r12d, PG_P + PG_RW + PG_ALLOC
	call	alloc_linAddr
	jc	k64err.allocLinAddr

	xor	ecx, ecx
	mov	[qword devInfo_1stFree], ecx
	mov	[qword devInfo_cnt], ecx
	mov	[qword devInfo], rax
	mov	[qword ioapInfo], rax
	mov	[qword ioapInfo_len], ecx
	mov	[qword devInfo_cnt], ecx
	mov	[qword devInfo_ioapMax], ecx

	mov	rax, 0x14'00000/16384
	mov	r8, rax
	shl	rax, 14
	mov	r9d, 0x200000/16384
	mov	r12d, PG_P + PG_RW + PG_ALLOC
	call	alloc_linAddr
	jc	k64err.allocLinAddr

	mov	qword [qword drvOnDisk], rax
	mov	dword [qword drvOnDisk_cnt], 0

	; map MADT
	;-------------------------------------

	mov	r9d, [qword acpi_apic + rmData]
	mov	r12d, [qword acpi_apic_len + rmData]
	cmp	r12d, 0x100000
	jge	.exit
	cmp	r12, 48
	jl	.exit

	mov	r8, acpiTbl + 3
	call	mapToKnownPT

	; parse MADT
	;-------------------------------------

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

	;reg	 rax, 403

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

	;reg	 rax, 403
	;shr	 eax, 16
	;movzx	 esi, al
	;shr	 eax, 8
	;reg	 rax, 205
	;reg	 rsi, 205

	cmp	ebp, eax
	jae	.1st_pass
	mov	[r10], ebp	; save largest lapic id
	jmp	.1st_pass

;----------------------------
.ioapic:
	;reg	 rax, 406

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


;===================================================================================================
; IOAPIC ID needs to be larger than largest LAPIC ID
; Intel MPSpecs v1.4 chapter "3.6.6 APIC Identification"
; ? may not exactly apply to x2Lapic IDs ?
;===================================================================================================

	; create mask of unused IDs
	mov	ecx, [r10]
	xor	ebp, ebp
	not	ebp
	cmp	ecx, 14
	jae	k64err
	add	ecx, 1
	shl	ebp, cl 		; EBP: bit set - ID free, bit cleared - ID taken
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


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================


	; reserve space for ioapic inputs
	;---------------------------------
	cld
	mov	esi, ioapic_inputCnt
	xor	eax, eax
	xor	ecx, ecx
	mov	edi, 4			; max 4 ioapics
@@:	lodsb
	add	ecx, eax		; += max inputs for each known ioapic
	dec	edi
	jnz	@b
	test	ecx, ecx
	jz	k64err.noIOAPICs

	imul	ecx, ioapInfo_sz
	mov	[qword ioapInfo_len], ecx
	cld
	mov	rdi, [qword ioapInfo]
	xor	eax, eax
	rep	stosb

	; setup default ISA -> IOAPIC mapping (will be overwritten by parsing MADT)
	;---------------------------------------------------------------------------
	mov	esi, [qword ioapInfo_len]
	add	rsi, [qword ioapInfo]
	mov	[qword devInfo], rsi
	xor	eax, eax
	xor	edi, edi
	mov	ecx, 16
@@:	mov	[rsi], edi
	mov	[rsi + 4], eax		; store default ACPI GlobIntNumber (temp location for this)
	mov	[rsi + 8], rdi		; default polarity=0, trigger=0, entry not present =0
	mov	[rsi + 16], rdi
	add	eax, 1
	add	rsi, devInfo_sz
	sub	ecx, 1
	jnz	@b

;===================================================================================================

	mov	r8, r9
	mov	r9, [qword devInfo]
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
	;reg	 rax, 403
	mov	ecx, [r8 + 4]		; ecx = GIN (GlobIntNum)
	shr	eax, 24 		; al  = isa irq
	;reg	 rcx, 404
	;reg	 rax, 404
	imul	edi, eax, devInfo_sz
	mov	[r9 + rdi + 4], ecx

	movzx	eax, byte [r8 + 8]
	and	eax, 1111b
	shl	eax, 6			; ah[1:0] = trigger, al[7:6] = polarity
	;reg	 rax, 404
	cmp	al, 10'000000b
	jnz	@f
	xor	al, al			; use bus default if reserved polarity supplied
@@:	cmp	ah, 10b
	jnz	@f
	xor	ah, ah			; use bus default if reserved trigger supplied
@@:	shr	ah, 1
	and	eax, 0x180
	shr	eax, 1			; bits [7:6], trig:pol
	mov	byte [r9 + rdi + 12], al
	;reg	 rax, 204
	jmp	.2nd_pass

;------------------------------------------
.nmi_lapic:
	jmp	.2nd_pass

;------------------------------------------
.nmi_ioapic:
	jmp	.2nd_pass


.2nd_pass_done:

;===================================================================================================
; loop thru all IOAPICs and its inputs, and set defaults

	mov	edi, ioapic_inputCnt-1
	mov	esi, ioapic-4096
.set_defaults:
	add	rdi, 1
	add	rsi, 4096
	movzx	ebp, byte [rdi]
	cmp	edi, ioapic_inputCnt+3
	ja	.defaults_set
@@:
	sub	ebp, 1
	jc	.set_defaults

	; clear everything to 0 and set mask bit
	lea	ecx, [rbp*2 + 0x11]
	mov	dword [rsi], ecx		; high dword
	mov	dword [rsi + 16], 0
	sub	ecx, 1
	mov	dword [rsi], ecx		; low dword
	mov	dword [rsi + 16], 0x10000	; mask interrupts

	jmp	@b
.defaults_set:

;===================================================================================================
; convert ACPI GlobIntNum into IOAPIC kernel_id and IOAPIC input for each ISA entry
;===================================================================================================

	mov	rsi, [qword devInfo]
	xor	ebp, ebp			; ebp = index
.IRQ_fix:
	mov	ecx, [rsi + 4]			; ecx = acpi glob int num
	xor	edi, edi			; edi = kernel ioapic id
	not	edi
@@:
	; start by enumerating thru 4 IOAPICs [0-3]
	add	edi, 1
	movzx	ebx, byte [qword ioapic_inputCnt + rdi]
	cmp	edi, 4
	jae	.invalid			; if no ioapic then all ioapic info is irrelevant

	mov	eax, [qword ioapic_gin + rdi*4]
	test	ebx, ebx			; zero ioapic inputs ?
	jz	@b
	cmp	eax, ecx
	ja	@b				; next ioapic if starting GIN > required
	add	ebx, eax
	cmp	ecx, ebx
	jae	@b				; next ioapic if required GIN outside this ioapic range
	sub	ecx, eax			; ecx = ioapic input, edi = ioapic kernel id
	cmp	ecx, 255
	ja	.invalid
	cmp	cl, [qword ioapic_inputCnt + rdi]
	jae	.invalid

	; DONE: ecx = ioapic input, edi = ioapic kernel id

	cmp	ebp, 2				; #2 used internally by 2 PICs, never used by ISA devs
	jz	.invalid
	cmp	ebp, 7				; #7 is PIC spurious IRQ (so can be #15)
	jnz	.valid

.invalid:
	xor	ecx, ecx
	mov	[rsi], rcx
	mov	[rsi + 8], rcx
	mov	[rsi + 16], rcx
	mov	[rsi + 24], ecx
	not	ecx
	mov	[rsi + 14], cx
	jmp	@f

.valid:
	or	edi, 0x20			; add present flags - bit 5
	xor	eax, eax
	mov	[rsi + 9], bpl			; source bus irq (low 4bits)
	or	[rsi + 12], dil 		; merge kernel ioapic id & present flag with pol/trig
	mov	[rsi + 13], cl			; ioapic input #
	mov	word [rsi + 14], -1		; no thread assigned
	mov	[rsi + 16], rcx 		; unknown vendor + device
	mov	[rsi + 24], eax 		; unknown classcode

	; assign 4byte dev_id (not optional, used to determine if bus input/pin valid)

	call	rand_tsc			; TSC is executed in predictable intervals :(
	shl	r8d, 16 			;    this random may change as dev driver is assigned
	lea	r8, [r8 + rbp + 1]		; "or r8d, ebp+1" = merge dev_id (starts with 1)
	mov	[rsi], r8d			;		    bit 15 =0 for non PCI
@@:
	add	ebp, 1
	add	rsi, devInfo_sz
	cmp	ebp, 16
	jb	.IRQ_fix

	mov	dword [qword devInfo_cnt], 16





;---------------- debug
macro sad{
	mov	rsi, [qword devInfo]
	reg	rsi, 101a
	mov	ecx, 16

@@:	reg	[rsi], 80a
	reg	[rsi + 4], 40b
	reg	[rsi + 9], 20b
	reg	[rsi + 12], 20b
	reg	[rsi + 13], 20b
	add	rsi, devInfo_sz
	sub	ecx, 1
	jnz	@b
}
;----------------

.exit:	clc
	ret






