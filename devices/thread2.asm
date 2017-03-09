
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



	; This file is compiled separately from the rest of the OS.
	; The resulted binary can be loaded from disk or inserted
	;	 into the OS compilation process using "file" command.

	format binary as ''
	use64
	org 0x8e'3273'2000


	include 'include_user.inc'
						  ; ? small hash for each 16KB of code ?
;===================================================================================================
header:
	dq 0,0			; encryption password (XTEA)
				;-------------------------------------------------------------------
	dq 0			; murmur2a checksum
				;-------------------------------------------------------------------
				; 1st  calc hash of unecrypted file (starting with "header size")
				; 2nd  compress file (starting with "checksum")
				; 3rd  xor 1st half of the file with 2nd half of of the file
				; 4th  change order of small blocks in file
				; 5th  encrypt resulted file with password (starting with "checksum")
				; THE PURPOSE IS TO RANDOMIZE FILE DATA WHEN IT IS SAVED/TRANSMITTED
				;-------------------------------------------------------------------
	db imports-header	; header size in bytes, any value <= 0x28 indicates ver 1 of the header
	dd _start - dat 	; length of initialized data section
	dw 0			; length of uninit data in 4KB (starts after code at multiple of 4KB addr)
	db 0			; flags: 0-exe, 1-lib, 3-drv
	dw dat.exports_len	; # of exports
	dw imports_len		; # of imports
	dd file_length		; max 256MB (bits 0-28)
;---------------------------------------------------------------------------------------------------
imports:    ; are we OK with writeable imports, exports & header ???

	reg64': 		      dd LIB_SYS, FUNC0_reg64
	syscall_k		      dq LIB_SYS + (FUNC0_syscall shl 32)
	sleep			      dq LIB_SYS + (FUNC0_thread_sleep shl 32)
	timer_in		      dq LIB_SYS + (FUNC0_timer_in shl 32)
	timer_exit		      dq LIB_SYS + (FUNC0_timer_exit shl 32)

	imports_len = ($-imports)/8

;---------------------------------------------------------------------------------------------------
; data section, also contains export functions(at the top), you can rewrite exports during runtime
;---------------------------------------------------------------------------------------------------
dat:
    .exports:
	dd 0x98324568		; func offset, 3bytes,	( top byte ignored?? )
	dd 0x12345678
    .exports_len = ($ - .exports)/4

db 0


; app can have a loop, it'll choose which rutine to run - suspend or init or smth else

; we can transfer control to the beginning of the code
; and attach a list of tasks that app needs to do - its up to the app what it wants to do

; maybe app wants to open large file first - then inititalize the device which is fast
; kernel may block some app actions unless others are done first

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

_start:
code1:
	add	byte [qword 160*24+txtVidMem + 40], 1	 ; 3rd green square at the bottom
	inc	[dat_.var1]

; this is not init but a loop which browses thru the tasks than need to be acomplished




; maybe one buffer - events that came first are saved first in that buffer (with input params)
; and a mask - which type of events are present
;


; which events can come out of order?

;====================================================================================
;OnDraw
;====================================================================================
; run drawing functions - only here
; during any other event user can request manual OnDraw event
;------------------------------------------------------------------
; Inside mouse event we can only set flag that smth needs to be redrawn
; then, when screen refresh comes (and after mouse moved/clicked) - thats 2 conditions - we
;	issue drawing commands/functions
; OnDraw can be invoked sooner if previous screen refresh was missed, in which situation we set
;	   a flag to indicate its not real screen refresh
;------------------------------------------------------------------
; say we are sitting in a mouseClick/mouseMove handlers and pulling these events(many,many) from main
; buffer then in the middle of separate handler executions - onDraw comes in - and we draw only once

; what if user moving or interracting with windows ? (kernel objects)
;------------------------------------------------------------------



; mouse DoubleClick:
; mouse dn, mouse up + mouse dn, mouse up (flag that part of next DoubleClick) first - then DoubleClick

; 4) timers

; 1) GUI related is one group, Actions actually, (including OnPrint, OnPaste, OnScreenshot, OnCopy, mouse, kbd, draw)

; 2) need this? or transfer device id in Action group? - Device related group (separated by device id)

; 3) Action related group (separated by action id), but nothing GUI related
;
;    netw packet came from eth0 or eth1 or lo
;    file changed/deleted/created on disk1 or usb2
;    filesystem was mounted on disk1 or disk2
;    connected disk3 (goes to file manager)
;    initialize disk3 (goes to device driver)

; File manager needs to know which file changed on all available device
; Single Device driver needss to know if its time to initialize the device
; File manager needs to know when to run initialization function as well (if fileMngr started)



; separate priority entries:
;------------------------------
; +0 1byte entry length
; +1 1byte need to finish eventID
; +2 several 1byte eventIDs that are ulocked when all +1 events processed
;    "to be unlocked" events are not yet listed in main buffer visible to user

code2:

	cmp	[dat_.var1], 21
	jz	.1
	cmp	[dat_.var1], 22
	jz	 .2
	jmp	  .end
;----------------------------------
.2:
	lea	rax, [rip]
	pushq	0x1003 rax
	call	qword [reg64']
	jmp	.end
;----------------------------------
.1:

	xor	r8, r8
	mov	r9, 0
	mov	r15, sys_intInstall
	;call	 [syscall_k]
	jmp	.end




.end:
	rdtsc
	shr	eax, 3
	and	eax, 7
	cpuid

	jmp	code1



; Timer handler needs to restore prev state of the thread: sleep or not sleep
  align 4
timer99:

	pushq	0x30f 0x48
	;call	 qword [reg64']

	mov	rax, [rsp + 8]
	pushq	0x1003 rax
	;call	 qword [reg64']
	mov	rax, [rsp + 16]
	pushq	0x1003 rax
	;call	 qword [reg64']

	add	rsp, [rsp]
	;jmp	 [timer_exit]


dat_:
.var1 dd 0


file_length = $-header

