
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
; input: r8[7:0]   - zero or desired vector in IDT (optional)
;	 r8[11:8]  - IST
;	 r8[12]    =1 if ISA, =0 if PCI
;	 r8[13]      PCI: =1 if r9 contains bus/dev/classcode, =0 if r9 contains dev/vendor id
;		     ISA: for ISA r9 always contains PNPID
;	 r8[63:14] - reserved
;	 r9	   - device id

dev_install:
	push	rbp rbx rax rcx rsi rdi

	; First, "dev_install" needs to load the driver from a disk IF necessary
	;		   which adds an entry to the data structure we are about to parse
	; Then we continue with our search bellow for the driver info.


	; its either 3 or 4 byte PNP/ACPI ID
	;---------------------------------------
	; (TODO: or it can be non-ascii(no guarantee) PCI,
	;    3byte classcode with leading non-ascii(guarantee) 0 byte
	;    located on the other side comparing to 3byte "PNP" zero byte
	;    We'll need multiple >>device<< entries as we want vendor specific extensions
	;							   (for 'generic' vendors :)


	bsr	rcx, r9
	cmp	ecx, 56
	setb	cl
	shl	ecx, 3
	shl	r9, cl
	mov	ebp, r9d
	shr	r9, 32			; device number (in ascii)	r9
	shr	ebp, cl 		; vendor string (in ascii)	   ebp

	; look for vendor first

	lea	rsi, [pnpName]
	xor	ecx, ecx
	add	ecx, [rsi]
	jz	.err_noVendors
	mov	rdi, rsi
	add	rsi, 4
@@:
	lodsq
	cmp	eax, ebp
	jz	@f
	sub	ecx, 1
	jnz	@b
	jmp	.err_noVendorInfo
@@:
	; then look for device for that vendor

	shr	rax, 32
	xor	ecx, ecx
	add	rdi, rax
	add	ecx, [rdi]
	jz	.err_noDevs
	add	rdi, 4
@@:
	cmp	[rdi], r9d
	jz	@f
	add	rdi, pnpName.sz
	sub	ecx, 1
	jnz	@b
	jz	.err_noDevInfo
@@:

	mov	r9d, [rdi + 8]		; offset relative to LMode
	mov	r12d, [rdi + 12]	; interrupt info
mov r12d, 8
	lea	rax, [LMode]
	add	r9, rax
	call	int_install		; input r8 remained unchanged thruought this function

	; call init function
	mov	eax, [rdi + 4]
	lea	rcx, [LMode]
	add	rax, rcx
	call	rax

.ok:	clc
.exit:
	pop	rdi rsi rcx rax rbx rbp
	ret

;----------------------------------------

; critical errors (incorrect code or data structures)
.err_noDevs:
	jmp	k64err

; non-critical errors
.err_noDevInfo:
.err_noVendorInfo:
.err_noVendors:
	jmp k64err
	stc
	jmp	.exit



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

int_install:
	movzx	ecx, r12b

	call	idt_setIrq

	lea	ecx, [rcx*2 + 0x11]
	and	r8d, 255
	mov	rsi, ioapic

	mov	dword [rsi], ecx
	mov	dword [rsi + 16], 0
	sub	ecx, 1
	mov	dword [rsi], ecx
	mov	dword [rsi + 16], r8d

	ret

;===================================================================================================
; input: r8[7:0]   - vector in idt
;	 r8[11:8]  - IST
;	 r9	   - handler mem address
; return: input r8 not modified

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

