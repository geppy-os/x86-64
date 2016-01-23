
; Distributed under GPL v1 License
; All Rights Reserved.


	org 0x29'9991'7000
	;org 0x200000
	use64
LMode:
	mov	eax, 0x10
	mov	ds, ax
	mov	ss, ax

	mov	r15, 0x400000
	lea	rsp, [kStack]

	; TSS setup
	;------------------------------
	lea	rbx, [tss_data]
	lea	r8, [interrupt_stack]
	lea	r9, [HPET1_stack]
	lea	rcx, [lapicT_stack]
	lea	rdi, [PF_stack]
	lea	rsi, [GP_stack]
	lea	rbp, [DF_stack]
	mov	[rbx + 4],r8
	mov	[rbx + 12],r8
	mov	[rbx + 20],r8
	mov	[rbx + 36], rcx
	mov	[rbx + 44], rdi
	mov	[rbx + 52], rsi
	mov	[rbx + 60], rbp
	mov	[rbx + 68], r9

	; setup another GDT
	;---------------------------------
	mov	rax, gdt
	mov	rsi, 0x00af'9a00'0000'ffff	; ring0 code
	mov	rcx, 0x00cf'9200'0000'ffff	; ring0 data
	mov	qword [rax], 0
	mov	qword [rax + 8], rsi		; kernel code, ring 0 CS for SYSCALL
	mov	qword [rax + 16], rcx		; kernel data,	      SS for SYSCALL

	mov	rdi, rbx
	mov	ecx, ebx
	shr	rbx, 32 			; dword 2 & 3
	shr	edi, 16
	shl	ecx, 16 			; dword 0
	ror	di, 8
	ror	edi, 8				; dword 1
	or	ecx, 0x67
	or	edi, 0x8900
	mov	[rax + 48], ecx
	mov	[rax + 52], edi
	mov	[rax + 56], rbx

	; switch to this GDT
	;---------------------------------

	mov	rcx, gdtr
	lea	rsi, [@f]
	mov	word  [rcx], 64-1
	mov	qword [rcx+2], rax
	lgdt	[rcx]
	push	8 rsi
	retf
@@:	mov	ecx, 0x10
	mov	ds, cx
	mov	ss, cx
	mov	es, cx

	; setup IDT
	;---------------------------------

	lea	rbp, [int_handlers]
	lea	rdi, [idt]
	lea	rsi, [_idt_exceptions_lmode]
	xor	ebx, ebx
	mov	rax, 0x8e00'0008'0000
.fill_IDT:
	movzx	ecx, word [rsi]
	add	rsi, 2
	test	ecx, ecx
	jz	@f
	add	rcx, rbp
	ror	ecx, 16
	ror	rcx, 16
	or	rcx, rax
	mov	[rdi + rbx], rcx
@@:	add	ebx, 16
	cmp	ebx, _idt_exceptions_lmode.cnt*16
	jb	.fill_IDT

	mov	byte [rdi + 14*16 + 4], 2	; #PF	for IST stack
	mov	byte [rdi + 13*16 + 4], 3	; #GP
	mov	byte [rdi +  8*16 + 4], 4	; #DF

	lea	rsi, [idtr]
	mov	word [rsi], 4095
	mov	[rsi+2], rdi
	lidt	[rsi]				; load IDT
	mov	eax, 48
	ltr	ax				; load TSS

;	 mov	 rax, cr0
;	 sti
;===================================================================================================

	call	acpi_parse_MADT 		; + setup IOAPICs & ISA->IOAPIC redirection


	; get lapic address
	mov	ecx, LAPIC_MSR
	rdmsr
	mov	ecx, edx
	bt	eax, 8
	jnc	k64err
	and	eax, not 4095
	shl	rcx, 32
	or	rax, rcx

	; map lapic
	mov	rcx, 0xffff'fff0'0000'0000
	mov	rdi, lapic shr 12
	or	rax, 10011b
	or	rcx, rdi
	shl	rdi, 12
	mov	[rcx*8], rax
	invlpg	[rdi]


	mov	eax, [qword lapic + LAPIC_VER]


	reg	rax, 80e




	call	init_RTC			; includes STI = enable interrupts








	; add human-readable errors


	mov	rax, [qword ioapic_gin]
	reg	rax, 102f

	jmp	$





;===================================================================================================
k64err:
	mov	rax, 'L O N G '
	mov	[qword 900], rax
	jmp	$

;===================================================================================================
reg64:
	pushfq
	push	rdx rbx rax rdi

	mov	ebx, [rsp + 56]
	mov	edx, 16
	mov	ah, bl
	shr	ebx, 8
	cmp	ebx, edx
	cmova	ebx, edx
	lea	edi, [rbx*2 + 2]
	xadd	[qword reg32.cursor], edi
	mov	rdx, [rsp + 48]
	lea	edi, [edi + ebx*2 - 2]
	std
.loop:
	mov	al, dl
	and	al, 15
	cmp	al, 10
	jb	@f
	add	al, 7
@@:	add	al, 48
	stosw
	ror	rdx, 4
	dec	ebx
	jnz	.loop

	pop	rdi rax rbx rdx
	popfq
	ret 16

	align 4
.cursor dd 0	; in bytes, 2bytes per symbol in text mode

;===================================================================================================
_idt_exceptions_lmode:
	dw	int_DE-int_handlers, int_DB-int_handlers, int_NMI-int_handlers
	dw	int_BP-int_handlers, int_OF-int_handlers, int_BR-int_handlers
	dw	int_UD-int_handlers, int_NM-int_handlers, int_DF-int_handlers
	dw	int_dummy2-int_handlers, int_TS-int_handlers, int_NP-int_handlers
	dw	int_SS-int_handlers, int_GP-int_handlers, int_PF-int_handlers
	dw	int_dummy1-int_handlers, int_MF-int_handlers, int_AC-int_handlers
	dw	int_MC-int_handlers, int_XM-int_handlers, int_VE-int_handlers
  .cnt = ($-_idt_exceptions_lmode)/2
