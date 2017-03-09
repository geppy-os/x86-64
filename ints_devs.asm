
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input:  r8  = 8byte id
;	  r9b =0 if PNP/ACPI, =1 if PCI, =2 if pci classcode
; return: r8 = pointer to driver entry if CF=0; unchanged if CF=1
;---------------------------------------------------------------------------------------------------
; preserves all regs

	align 4
drv_find:
	push	r12 rax
	mov	r12, [qword drvOnDisk]
	mov	eax, [qword drvOnDisk_cnt]
.loop:
	sub	eax, 1
	jc	.exit
	cmp	[r12], r8
	jnz	@f
	cmp	[r12 + 10], r9b
	jz	.ok
@@:	add	r12, drvOnDisk_sz
	jmp	.loop

.ok:	mov	r8, r12
	clc
.exit:	pop	rax r12
	ret

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8d	   = kernel device id
;	 r9	   = 8byte interrupt handler address
;	 r12b	   = optional: 0 or idt entry
;	 r12[10:8] = optional: IST (ignored if r12b=0)
;---------------------------------------------------------------------------------------------------
; TODO: can call this function multiple times if MSI-X supported with different r9 (need int_remove)
;										   maybe int_replace
	align 4
int_install:
	push	rax rcx rdi rsi rdx rbx rbp r12


	mov	esi, r8d
	and	esi, 0x7fff
	mov	r13, [qword devInfo]
	sub	esi, 1
	jc	k64err.smallDevNum
	cmp	[qword devInfo_cnt], esi
	jbe	.hotplug


	imul	esi, devInfo_sz
	add	r13, rsi			; r13 - devInfo entry for the input kernel dev_id
	cmp	[r13], r8d
	jnz	k64err.invalidDevID

	; take first valid ioapic info and use it
	mov	esi, 10 			; r13+rsi = ptr to one of 2 words that tell ioapic info
	test	byte [r13 + 10], 0x20
	jnz	@f
	add	esi, 2
	test	byte [r13 + 12], 0x20
	jnz	@f
	jmp	k64err.intInst_noIoapInfo
@@:
	; find if any int handler present for this ioapic+input combination
	;------------------------------------------------------------------

	mov	eax, [qword ioapic_inputCnt]
	mov	ecx, [r13 + rsi]
	and	ecx, 11b			; ioapic id, max 4 values
	movzx	r12d, byte [r13 + rsi + 1]	; input #
	xor	edx, edx
	xor	ebx, ebx			; number of inputs to skip to reach needed ioapic id
@@:
	cmp	edx, ecx
	jz	@f				; jump if reached needed ioapic id
	movzx	ebp, al
	add	edx, 1
	add	ebx, ebp
	shr	eax, 8
	jmp	@b
@@:

	mov	eax, r12d			; AL = input #
	imul	ebx, ioapInfo_sz
	imul	r12d, ioapInfo_sz
	mov	r14, [qword ioapInfo]		; r14 - ioapic info array
	lea	r12d, [r12 + rbx + ioapInfo_sz]
	cmp	[qword ioapInfo_len], r12
	jb	k64err.intInst_destIoapInptOutsideMem
	sub	r12d, ioapInfo_sz
	add	r14, r12			; r14 - specific ioapic info entry

;==========  shared interrupt  =====================================================================

	test	 dword [r13 + 8], 1		; can dev driver distinguish betw its irq and other devs?
	jnz	 .nonSharedInt			; jump if no

; need to check polarity & trigger for the shared

	jmp	.done

;===================================================================================================
.nonSharedInt:
	mov	ebp, [r13 + rsi]
	test	dword [r14 + 2], 0x7fff 	; do we have a handler already present ?
	jnz	k64err.intInst_nonShared
	test	byte [r14], 100b
	jnz	k64err.intInst_nonSharedP

	or	byte [r13 + rsi], 4		; flag that this byte was used for irq setup
	and	ebp, 11000011b			; mask bits 2,3,4,5
	or	ebp, 100b			; set if  non-shared int handler present

	xor	ebx, ebx
	mov	[r14 + 4], rbx			; bytes [4:11] zeroed
	mov	[r14], bpl
	mov	[r14 + 1], al
	mov	[r14 + 2], r8d

	jmp	.setup_irq

;===================================================================================================
.hotplug:
	jmp	k64err.largeDevNum


;===================================================================================================
; Setup either MAIN shared int handler (which calls dev driver irq rutines), or single non-shared.

.setup_irq:
	movzx	ebp, byte [rsp]
	test	ebp, ebp
	jnz	.update_IDT			; skip finding new IDT entry if one supplied

	; find empty entry in IDT
	; got lousy 8 entries with this simple loop
	mov	ebp, 52 			; starting entry - EBP
@@:	mov	edi, ebp
	shl	edi, 4
	cmp	qword [idt + rdi], 0
	jz	.update_IDT
	add	ebp, 16 			;  advance by 16 entries
	cmp	ebp, 192
	jb	@b
	jmp	k64err.intInst_noFreeIDTe

.update_IDT:
	xor	r8d, r8d
	cmp	byte [rsp], 0
	jz	@f				; jump if input idt entry = 0 (ignore IST as well)
	mov	r8b, [rsp + 1]
	and	r8d, 111b			; IST
	shl	r8d, 8
@@:	or	r8d, ebp
	call	idt_setIrq

	; get IOAPIC addr for the needed entry
	shl	ecx, 12
	add	ecx, ioapic
	lea	eax, [rax*2 + 0x10]

	; a few precautions before IOAPIC setup
	mov	dword [rcx], eax		; low dword
	mov	edi, [rcx + 16]
	test	dil, dil
	jnz	k64err.handlerPresent
	bt	edi, 16
	jnc	k64err.notMasked


	movzx	edi, byte [lapicID]		; cpu id for physical mode
	add	eax, 1
	shl	edi, 24
	mov	dword [rcx], eax
	mov	dword [rcx + 16], edi

	mov	edi, [r13 + rsi]
	and	edi, 1100'0000b 		; trigger top bit, polarity - lower
	shl	edi, 1
	shr	dil, 1
	shl	edi, 7
	or	edi, ebp
	sub	eax, 1
	mov	dword [rcx], eax
	mov	dword [rcx + 16], edi

;---------------------------------------------------------------------------------------------------
.done:	pop	r12 rbp rbx rdx rsi rdi rcx rax
	ret


















macro asd{
;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8d	   = 4byte unique id given to device driver during initialization
;	 r8[63:32] = 0
;	 r9	   = 8byte interrupt handler address ( bellow 4GB )
;	 r12	   = 0 or preffered source bus IRQ number (used if automatic retrival problematic)
;	 r13	   = TODO: user data passed to installed interrupt handler (how many bytes & where)
;---------------------------------------------------------------------------------------------------
; TODO: can call this function multiple times if MSI-X supported with different r9 (need int_remove)
;										   maybe int_replace

; for RTC, need to setup vendor+device in devInfo array

	align 8
int_install__:
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
	;	     This simply consumes CPU power. Nothing more.

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
	}

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input: r8[7:0]   - vector in IDT
;	 r8[11:8]  - IST
;	 r9	   - 8byte handler mem address
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

