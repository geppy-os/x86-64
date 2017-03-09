
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



	; This file is compiled separately from the rest of the OS.
	; The resulted binary can be loaded from disk or inserted
	;	 into the OS compilation process using "file" command.

	format binary as ''
	use64
	org 0x8e'3273'2000


	include 'user_include.inc'

;===================================================================================================
header:
	dq 0,0
	dq 0
	db imports-header
	dd _start - dat
	dw 0
	db 0
	dw 0
	dw imports_len
	dd file_length
;---------------------------------------------------------------------------------------------------
imports:
	reg64'			dq LIB_SYS + (FUNC0_reg64 shl 32)
	syscall_k		dq LIB_SYS + (FUNC0_syscall shl 32)

imports_len = ($-imports)/8

;---------------------------------------------------------------------------------------------------
dat:

    .var1 dd 0

    .job	dd 0

;===================================================================================================
;///////////////////////       PS2 Mouse & Keyboard driver	 ///////////////////////////////////
;===================================================================================================

_start:
	.hdr = (((_start-header)+4095) and 0xfffff000)

	add	byte [qword 160*24+txtVidMem + 44], 1	 ; 4th green square at the bottom
	inc	[dat.var1]


	cmp	[dat.var1], 20
	jnz	.22

	xor	eax, eax
	lea	rax, [rip]
	pushq	0x1003 rax
	call	[reg64']



	lea	r9, [ps2_kbd_handler]
	xor	r12, r12
	mov	r8d, [_start-.hdr-8]
	mov	r15d, sys_intInstall
	call	[syscall_k]

	lea	r9, [ps2_mouse_handler]
	xor	r12, r12
	mov	r8d, [_start-.hdr-4]
	mov	r15d, sys_intInstall
	call	[syscall_k]



@@:	in	al, 0x64
	bt	eax, 1
	jc	@b

	mov	al, 0xa8
	out	0x64, al

	mov	r8d, 5*1000
	mov	r15, sys_sleep
	call	[syscall_k]



@@:	in	al, 0x64
	bt	eax, 1
	jc	@b
	;---------------------------------
	mov	al, 0x20
	out	0x64, al

@@:	in	al, 0x64
	bt	eax, 0
	jnc	@b

	in	al, 0x60
	pushq	0x20a rax
	call	[reg64']
	or	al, 2
	mov	ebx, eax
	;---------------------------------





@@:	in	al, 0x64
	bt	eax, 1
	jc	@b
	;---------------------------------
	mov	al, 0x60
	out	0x64, al

@@:	in	al, 0x64
	bt	eax, 1
	jc	@b

	mov	al, bl
	out	0x60, al
	;---------------------------------





	mov	r8d, 5*1000
	mov	r15, sys_sleep
	call	[syscall_k]

@@:	in	al, 0x64
	bt	eax, 1
	jc	@b
	;---------------------------------
	mov	al, 0x20
	out	0x64, al

@@:	in	al, 0x64
	bt	eax, 0
	jnc	@b

	in	al, 0x60
	pushq	0x20a rax
	call	[reg64']
	;---------------------------------

	mov	r8d, 5*1000
	mov	r15, sys_sleep
	call	[syscall_k]





	mov	r8d, 0xf6
	call	ps2_mouseSend


	mov	r9d, 8
@@:	sub	r9d, 1
	jz	@f
	in	al, 0x64
	test	al, 1
	jz	@b
	in	al, 0x60
	pushq	0x204 rax
	call	[reg64']
	jmp	@b
@@:




	mov	r8d, 0xf4
	call	ps2_mouseSend


	mov	r9d, 8
@@:	sub	r9d, 1
	jz	@f
	in	al, 0x64
	test	al, 1
	jz	@b
	in	al, 0x60
	pushq	0x204 rax
	call	[reg64']
	jmp	@b
@@:



.22:
	rdtsc
	shr	eax, 3
	and	eax, 7
	cpuid



	jmp	_start

;===================================================================================================
; all interrupt handlers are executed in ring0

	align 8
ps2_kbd_handler:
	push	rax

	in	al, 0x60

	push	0x21a rax
	call	[reg64']

;	 cmp	 al, 1
;	 jnz	 @f
;	 call	 reboot 	 ; reboot if Esc key pressed down
;@@:

	pop	rax
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

.len = $-ps2_kbd_handler

;===================================================================================================
; all interrupt handlers are executed in ring0

	align 8
ps2_mouse_handler:
	push	rax

	in	al, 0x60

	push	0x204 rax
	call	[reg64']

	pop	rax
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq

.len = $-ps2_mouse_handler





macro asd{


	align 8
ps2_mouse_handler3:
	push	r15 rax rcx rbx rsi rdi rbp r8 r9

	mov	r15, 0x400000
	in	al, 0x60

	mov	esi, [ps2_packetCnt]
	cmp	esi, 0
	jl	.mouse_init
	jne	@f
	test	eax, 1 shl 3			; first packet, bit3 must be 1
	jz	.reinit_mouse
@@:
	add	dword [ps2_packetCnt], 1
	mov	edi, [ps2_packetMax]
	mov	[ps2_mouseBytes + rsi], al
	cmp	dword [ps2_packetCnt], edi
	jnz	.exit
	;---------------------------------------

	; TODO: use less PUSH/POP registers until we got here

	mov	eax, [ps2_mouseBytes]
	movzx	ecx, al 			; flags 	  CX
	movzx	esi, ah 			; x	       SI
	shr	eax, 16 			; y	    AX
	mov	edi, 0xff
	bt	ecx, 6				; x overlow
	cmovc	esi, edi
	bt	ecx, 7				; y overflow
	cmovc	eax, edi
	ror	esi, 8
	ror	eax, 8
	bt	ecx, 4
	cmovc	si, di
	bt	ecx, 5
	cmovc	ax, di
	xor	ebx, ebx			; z	    BX
	rol	esi, 8
	rol	eax, 8

	cmp	dword [ps2_packetCnt], 4
	jb	.save_info

	mov	bl, [ps2_mouseBytes + 3]

.save_info:
	neg	ax
	call	mouse_add_data

	mov	dword [ps2_packetCnt], 0
.exit:
	;mov	 dword [qword lapic + LAPIC_EOI], 0
	pop	r9 r8 rbp rdi rsi rbx rcx rax r15
	ret
;===================================================================================================

.reinit_mouse:
	reg	rax, 26f
	mov	dword [ps2_packetCnt], -1
	jmp	.exit

.mouse_init:
	reg	rax, 26f
	jmp	.exit




	align 8
ps2_mouse_handler2:
	push	r15 rax rcx rbx rsi rdi rbp r8 r9

	mov	r15, 0x400000
	in	al, 0x60

	mov	esi, [ps2_packetCnt]
	cmp	esi, 0
	jl	.mouse_init
	jne	@f
	test	eax, 1 shl 3			; first packet, bit3 must be 1
	jz	.reinit_mouse
@@:
	add	dword [ps2_packetCnt], 1
	mov	edi, [ps2_packetMax]
	mov	[ps2_mouseBytes + rsi], al
	cmp	dword [ps2_packetCnt], edi
	jnz	.exit
	;---------------------------------------

	; TODO: use less PUSH/POP registers until we got here

	mov	eax, [ps2_mouseBytes]
	movzx	ecx, al 			; flags 	  CX
	movzx	esi, ah 			; x	       SI
	shr	eax, 16 			; y	    AX
	mov	edi, 0xff
	bt	ecx, 6				; x overlow
	cmovc	esi, edi
	bt	ecx, 7				; y overflow
	cmovc	eax, edi
	ror	esi, 8
	ror	eax, 8
	bt	ecx, 4
	cmovc	si, di
	bt	ecx, 5
	cmovc	ax, di
	xor	ebx, ebx			; z	    BX
	rol	esi, 8
	rol	eax, 8

	cmp	dword [ps2_packetCnt], 4
	jb	.save_info

	mov	bl, [ps2_mouseBytes + 3]

.save_info:
	neg	ax
	call	mouse_add_data

	mov	dword [ps2_packetCnt], 0
.exit:
	mov	dword [qword lapic + LAPIC_EOI], 0
	pop	r9 r8 rbp rdi rsi rbx rcx rax r15
	iretq

	; kogda uspeli togda i uspeli s etimi oknami
	; we have screen refresh every N milliseconds, so this is when we mess with the X and Y

	; mouse bits are needed to increase cryptography strength, like in TrueCrypt

;===================================================================================================

.reinit_mouse:
	reg	rax, 26f
	mov	dword [ps2_packetCnt], -1
	jmp	.exit

.mouse_init:
	reg	rax, 26f
	jmp	.exit
}

;===================================================================================================

ps2_mouseSend:
	push	rax rcx
	mov	r9d, 0xd4
@@:
	; wait for input buffer to be empty to send new byte in
	mov	ecx, 65535
@@:	in	al, 0x64
	test	al, 10b
	jz	@f
	loop	@b
	;jmp	 k64err
@@:
	; tell ps2 controller that next byte will be for 1st/2nd ps2 device
	mov	al, r9b
	out	0x64, al

	; wait for input buffer to be empty to send new byte in
	mov	ecx, 65535
@@:	in	al, 0x64
	test	al, 10b
	jz	@f
	loop	@b
	;jmp	 k64err
@@:
	; send the actual value to 1st/2nd device
	mov	al, r8b
	out	0x60, al

	mov	r8d, 5*1000
	mov	r15, sys_sleep
	call	[syscall_k]

	pop	rcx rax
	ret

file_length = $-header

