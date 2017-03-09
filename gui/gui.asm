
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


include 'mouse.asm'


;===================================================================================================



;===================================================================================================
; input: [rsp]	    = # of bytes on stack. To be added to RSP register for "ret" to execute properly
;	 [rsp + 8]  = user data1
;	 [rsp + 16] = user data2
;	 [rsp + 24] = undefined (time in ?microseconds at which this timer event was scheduled)
;---------------------------------------------------------------------------------------------------
; this is a timer handler, and it needs to save/restore all register used


	align 8
screen_update:
.sz=120
	pushfq
	sub	rsp, .sz
	mov	[rsp], rax
	mov	[rsp + 8], rcx
	mov	[rsp + 16], rdx
	mov	[rsp + 24], rsi
	mov	[rsp + 32], rdi
	mov	[rsp + 40], rbx
	mov	[rsp + 48], rbp
	mov	[rsp + 56], r15
	mov	[rsp + 64], r9
	mov	[rsp + 72], r10
	mov	[rsp + 80], r11
	mov	[rsp + 88], r12
	mov	[rsp + 96], r13
	mov	[rsp + 104], r14
	mov	[rsp + 112], r8


	mov	rax, [rsp + .sz+16]	; user data1
	reg	rax, 43f
	mov	rax, [rsp + .sz+24]	; user data2
	reg	rax, 43f


	mov	r8d, 625*100		; 62.5ms
	lea	r9, [screen_update]
	call	timer_in


	mov	rax, [rsp]
	mov	rcx, [rsp + 8]
	mov	rdx, [rsp + 16]
	mov	rsi, [rsp + 24]
	mov	rdi, [rsp + 32]
	mov	rbx, [rsp + 40]
	mov	rbp, [rsp + 48]
	mov	r15, [rsp + 56]
	mov	r9, [rsp + 64]
	mov	r10, [rsp + 72]
	mov	r11, [rsp + 80]
	mov	r12, [rsp + 88]
	mov	r13, [rsp + 96]
	mov	r14, [rsp + 104]
	mov	r8, [rsp + 112]
	add	rsp, .sz
	popfq
	add	rsp, [rsp]
	ret



