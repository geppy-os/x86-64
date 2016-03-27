
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



;===================================================================================================
ps2_init:


	; need real life polarity/trigger before code published online

	mov	dword [ps2_packetMax], 3
	mov	dword [ps2_packetCnt], -1

	mov	r8d, 0x0d0
	lea	r9, [ps2_kbd_handler]
	mov	r12, 0x00'01
	call	int_install

	mov	r8d, 0x0d1
	lea	r9, [ps2_mouse_handler2]
	mov	r12, 0x00'0c
	call	int_install



@@:	in	al, 0x64
	bt	eax, 1
	jc	@b

	mov	al, 0xa8
	out	0x64, al

	mov	r8d, 5*1000
	call	sleep




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
	reg	rax, 20a
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
	call	sleep

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
	reg	rax, 20a
	;---------------------------------

	mov	r8d, 5*1000
	call	sleep





	mov	r8d, 0xf6
	call	ps2_mouseSend


	mov	r9d, 8
@@:	sub	r9d, 1
	jz	@f
	in	al, 0x64
	test	al, 1
	jz	@b
	in	al, 0x60
	reg	rax, 204
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
	reg	rax, 204
	jmp	@b
@@:


	mov	dword [ps2_packetCnt], 0



ret



;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

;ps2_kbdSend:
;	 push	 rax rcx
;	 mov	 r9d, 0xd2
;	 jmp	 @f

ps2_mouseSend:
	push	rax rcx
	mov	r9d, 0xd4
@@:
	; wait for input buffer to be empty, to send new byte in
	mov	ecx, 65535
@@:	in	al, 0x64
	test	al, 10b
	jz	@f
	loop	@b
	jmp	k64err
@@:
	; tell ps2 controller that next byte will be for 1st/2nd ps2 device
	mov	al, r9b
	out	0x64, al

	; wait for input buffer to be empty, to send new byte in
	mov	ecx, 65535
@@:	in	al, 0x64
	test	al, 10b
	jz	@f
	loop	@b
	jmp	k64err
@@:
	; send the actual value to 1st/2nd device
	mov	al, r8b
	out	0x60, al

	mov	r8d, 5*1000		; 5ms
	call	sleep

	pop	rcx rax
	ret

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

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

	; TODO: use less PUSH/POP registers unless we got here

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

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
	align 8
ps2_kbd_handler:
	push	rax		   ; there is no auto repeat on usb keyboards

	in	al, 0x64
	reg	rax, 214	; red on blue bgr
	in	al, 0x60
	reg	rax, 21a	; green on blue bgr

	mov	dword [qword lapic + LAPIC_EOI], 0
	pop	rax
	iretq




;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

	align 8
ps2_mouse_handler:
	push	rax
	mov	rax, -1
	reg	rax, 100f
	mov	dword [qword lapic + LAPIC_EOI], 0
	pop	rax
	iretq







