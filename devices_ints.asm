
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8b  entry type, =0 if ISA, =1 if PCI, >=2 reserved
;	 r9   - device id

	align 8
dev_install:
	push	rax rcx rdi rsi

	and	r8d, 0xff
	mov	edi, r8d
	call	dev_find
	mov	rax, r8
	jc	.err


	; BIG TODO:
	; we have to figure how to distribute interrupts (in this function or somewhere else)

; priorities:
;-----------------------
; high priority 								 low priority
;	<- rtc/hpet, network, usb, usb, usb, ps2, local disk, cd, lapic_timer, hpet ->


	mov	ecx, [rax + 8]
	cmp	edi, 1
	mov	word [rax + 8], 0
	mov	byte [rax + 10], 0
	jb	.ISA_ACPI
	jz	.PCI
	jmp	.err
;---------------------------------------------------------------------------------------------------
.PCI:

	jmp	.get_id

;---------------------------------------------------------------------------------------------------
.ISA_ACPI:
	mov	r8d, isaDevs
	mov	r9d, ecx
	shr	ecx, 28
	jz	@f

	; process 1st source irq from isa/acpi
	imul	ecx, 20
	mov	r14d, 0xff
	mov	r13d, 0x0f
	movzx	edi, byte [r8 + rcx + 12]	; kernel ioapic id, 2bits
	movzx	ecx, byte [r8 + rcx + 11]	; ioapic input
	bt	edi, 7
	cmovnc	r14d, r13d			; 0 (not valid src irq) if ioapic entry not valid
	and	edi, 3
	shl	edi, 4
	or	edi, 0x80			; indicates that this is ISA device
	and	[rax + 11], r14b		; keep/delete 4bit src irq (0 is not a valid irq)
	mov	[rax + 10], cl			; 8byte ioapic input
	or	[rax + 8], dil			; 2bit ioapic kerlel_id + 2bit flags
@@:
	;---------------------------------------
	shr	r9d, 24
	and	r9d, 0xf
	jz	.get_id

	; process 2nd source irq from isa/acpi
	imul	r9d, 20
	mov	r14d, 0xff
	mov	r13d, 0xf0
	movzx	edi, byte [r8 + r9 + 12]
	movzx	ecx, byte [r8 + r9 + 11]
	bt	edi, 7
	cmovnc	r14d, r13d
	and	edi, 3
	or	edi, 0x08
	and	[rax + 11], r14b
	mov	[rax + 9], cl
	or	[rax + 8], dil

;---------------------------------------------------------------------------------------------------
.get_id:

	; calculate 2byte unique ID for the device driver
	call	rand_tsc
	mov	r12d, inst_devs_cnt
	mov	r14d, inst_devs
	mov	r13d, 1
	xadd	[r12], r13d			; get 2byte array index
	shl	r13d, 16
	or	r8, r13 			; merge unique id with array index (4byte unique id)

	mov	ecx, [rax + 4]
	lea	r9, [LMode]
	add	rcx, r9

	; save unique id & device info address
	shr	r13d, 16
	imul	r13d, 12
	mov	[r14 + r13], r8d
	mov	[r14 + r13 + 4], rax

	; call init function
	reg	r8, 816
	push	r8
	call	rcx

	clc
.exit:
	pop	rsi rdi rcx rax
	ret
.err:
	stc
	jmp	.exit

; ISA IDE disk tells us which interrupt triggered (int handler needs input data)
; and calls int_remove on unused interrupt vector

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input:  r8b  entry type, =0 if ISA, =1 if PCI, >=2 reserved
;	  r9   - device id
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
; input: r8d	   = 4byte unique id given to device driver during initialization
;	 r8[63:32] = 0
;	 r9	   = 8byte interrupt handler address ( bellow 4GB :)
;	 r12	   = 0 or preffered source bus IRQ number (used if automatic retrival problematic)
;	 r13	   = TODO: user data passed to installed interrupt handler (how many bytes & where)
;---------------------------------------------------------------------------------------------------
; TODO: can call this function multiple times if MSI-X supported with different r9 (need int_remove)
;										   maybe int_replace

	align 8
int_install:
	pushf
	push	rax rcx rsi rdi rbp r9
	cli

	mov	ecx, r8d
	shr	r8d, 16
	mov	r14, inst_devs
	cmp	[qword inst_devs_cnt], r8d
	jbe	.err
	imul	r8d, 12
	cmp	[r14 + r8], ecx
	jnz	.err
	mov	r14, [r14 + r8 + 4]		; pointer to dev info in "devices.inc"
	;----------------------------------------

	mov	ecx, [r14 + 8]			; 4byte ioapic info
	mov	esi, ecx
	shr	ecx, 24
	and	ecx, 0xf			; low irq (2nd)
	and	r12d, 0xff
	jz	.auto_select_irq		; irq 0 is not a valid irq
	bt	esi, 3				; check if 2nd IRQ is ISA
	jnc	@f				; jump if not
	cmp	r12d, ecx
	jnz	@f
	mov	r12, 1				; start search with 2nd irq (last)
	jmp	.auto_select_irq
@@:	xor	r12, r12			; start search with 1st irq (first)

	; choose 1st availble source IRQ
.auto_select_irq:
	mov	ecx, 28 			; 28 - 4bit   16 - 8bit   4 - 2bit
	mov	edi, 16 			; 24	       8	  0
	mov	eax, 4
	mov	r8d, 24
	mov	r9d, 8
	xor	r10, r10
	cmp	r12d, 1
	mov	ebp, esi
	cmovz	ecx, r8d
	cmovz	edi, r9d
	cmovz	eax, r10d
	shr	ebp, cl
	add	r12d, 1
	and	ebp, 0xf
	jnz	.install_irq
	cmp	r12d, 1
	jbe	.auto_select_irq
	jmp	.err				; if ebp=0 then no interrupt info

;---------------------------------------------------------------------------------------------------
.install_irq:

	; get ioapic info from source irq entry
	mov	ecx, eax
	mov	eax, esi
	shr	esi, cl
	mov	ecx, edi
	and	esi, 3				; ioapic id	      ESI
	shr	eax, cl
	shl	esi, 12
	and	eax, 0xff			; ioapic input	      EAX
	lea	rdi, [rsi + ioapic]		; ioapic addr	      EDI

	; get interrupt info from ioapic
	lea	eax, [rax*2 + 0x10]
	mov	dword [rdi], eax		; low dword	      ESI
	mov	esi, [rdi + 16]
	test	sil, sil
	jnz	.dev_handler

;---------------------------------------------------------------------------------------------------

	; find empty entry in IDT
	mov	ebp, 52
@@:	cmp	dword [shared_IRQs + rbp*4], 0
	jz	@f
	add	ebp, 16
	cmp	ebp, 192
	jb	@b
	jmp	.err
@@:
	; copy shared int handler to new address
	mov	r9d, int_shared.sz
	mov	r8, r9
	lock
	xadd	[qword kernelEnd_addr], r9d
	mov	ecx, -1
	mov	r12, r9
	cmp	r9, rcx
	ja	k64err.shareIndHandler_largeAddr
	lea	rcx, [int_shared]
	test	r8d, 7
	jnz	k64err.sharedIntHandler
	shr	r8d, 3
	shr	r8d, 1
	jnc	@f
	mov	r10, [rcx]
	mov	[r9], r10
	jz	k64err.sharedIntHandler
	add	rcx, 8
	add	r9, 8
@@:	mov	r10, [rcx]
	mov	r11, [rcx + 8]
	mov	[r9], r10
	mov	[r9 + 8], r11
	add	rcx, 16
	add	r9, 16
	sub	r8d, 1
	jnz	@b

	cmp	qword [r12 + ((int_shared.sz2+15) and 0xfffff0)], 0
	jnz	k64err.wrongSharedIntCount

	; reserve IDT entry for the newly copied handler
	mov	[shared_IRQs + rbp*4], r12d
	mov	sil, bpl			; update vector for IOAPIC entry

	; update IDT
	mov	rcx, r12
	mov	r9, r12
	movzx	r8d, bpl
	call	idt_setIrq

	; update IOAPIC
	btr	esi, 16 			; remove mask bit
	mov	dword [rdi], eax		; high dword
	mov	[rdi + 16], esi

	; shared int handler can fire now, with 0 device functions to call
	;    will be non-stop int firing if devices don't take precaution before calling int_install
	;	     consumes resources, that's all

;---------------------------------------------------------------------------------------------------
.dev_handler:

	; add device handler to the shared interrupt

	movzx	ebp, sil
	mov	ecx, [shared_IRQs + rbp*4]
	mov	esi, [rcx + ((int_shared.sz2+15) and 0xfffff0)]
	mov	eax, [rsp]
	cmp	esi, int_shared.max		; constants from "int_handlers.asm"
	jae	.err

	add	dword [rcx + ((int_shared.sz2+15) and 0xfffff0)], 1
	mov	qword [rcx + rsi*8 + 8 + ((int_shared.sz2+15) and 0xfffff0)], rax

	clc
.exit:
	add	rsp, 8
	pop	rbp rdi rsi rcx rax
	popf
	ret
.err:
	stc
	jmp	.exit

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

