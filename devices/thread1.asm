
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



	; This file is compiled separately from the rest of the OS.
	; The resulted binary can be loaded from disk or inserted
	;	 into the OS compilation process using "file" command.

	format binary as ''
	use64
	org 0x8e'3273'2000


	include 'include_user.inc'

;===================================================================================================
header:
	dq 0,0
	dq 0
	db imports-header
	dd _start - dat
	dw 0
	db 0
	dw dat.exports_len
	dw imports_len
	dd file_length
;---------------------------------------------------------------------------------------------------
imports:

	reg64': 		dd LIB_SYS, FUNC0_reg64
	dd2asciiDec':		dd LIB_SYS, FUNC0_dd2asciiDec
	syscall_k		dq LIB_SYS + (FUNC0_syscall shl 32)
	sleep			dq LIB_SYS + (FUNC0_thread_sleep shl 32)
	timer_in		dq LIB_SYS + (FUNC0_timer_in shl 32)
	timer_exit		dq LIB_SYS + (FUNC0_timer_exit shl 32)

	imports_len = ($-imports)/8
;---------------------------------------------------------------------------------------------------
dat:
    .exports:
	dd 0x98324568
	dd 0x12345678
    .exports_len = ($ - .exports)/4

.var1 dd 0

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

_start:
code1:
	add	byte [qword 160*24+txtVidMem + 36], 1	 ; 2nd green square at the bottom
	inc	[dat.var1]

code2:
	mov	rax, 0x1010
	push	rax
	pop	rax



	cmp	[dat.var1], 5099750
	jz	.1
	cmp	[dat.var1], 5599750
	jz	.2

	cmp	[dat.var1], 6
	ja	@f



	;pushfq
	;push	 rax
	;mov	 rax, 0x55
	;pushq	 0x30c rax

	;call	 qword [dd2asciiDec']

	;pop	 rax
	;popfq


	mov	rax, 0x55
	pushq	0x30b rax
	call	qword [reg64']
	jmp	code1



@@:
	;mov	 r8d, 1
	;xor	 r9, r9
	;xor	 r12, r12
	;call	 [sleep]
	jmp	code1

.2:
	pushq	0x30b 0x77
	call	qword [reg64']
	jmp	code1
.1:

	pushq	0x30b 0x60
	call	qword [reg64']

	;mov	 r8d, 1
	;call	 [sleep]


	;mov	 r8d, 300'000
	;lea	 r9, [timer99]
	;mov	 r12, 0x0808080808080808
	;mov	 r13, 0x9090909090909090
	;mov	 r15d, sys_timerIn
	;call	 [syscall_k]

	mov	r8d, 1
	mov	r9d, 999000
	mov	r15, sys_sleep
	call	[syscall_k]

	pushq	0x30b 0x62
	call	qword [reg64']

	jmp	code1



; Timer handler needs to restore prev state of the thread: sleep or not sleep
  align 4
timer99:

	pushq	0x30b 0x61
	call	qword [reg64']

	mov	rax, [rsp + 8]
	pushq	0x1007 rax
	call	qword [reg64']
	mov	rax, [rsp + 16]
	pushq	0x1007 rax
	call	qword [reg64']

	add	rsp, [rsp]
	jmp	[timer_exit]


dq 0x4747474747474747
dq 0x4747474747474747
dq 0x3535353535353535
dq 0x3535353535353535



file_length = $-header

