
int_handlers:

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

	; must be 16byte aligned
	align 16
int_shared:
	push	r8 rax rcx rsi rdi rbp rbx rdx	0
@@:
	mov	ecx, [rsp]
	lea	rsi, [.handlers]
	cmp	[.handlers], ecx
	jbe	@f
	mov	ecx, [rsi + 8 + rcx*8]
	call	rcx			; TODO: function needs to return confirmation if this
	add	dword [rsp], 1						     ; is its device or not
	jmp	@b
@@:
	mov	rdx, [rsp + 8]
	mov	rbx, [rsp + 16]
	mov	rbp, [rsp + 24]
	mov	rdi, [rsp + 32]
	mov	rsi, [rsp + 40]
	mov	rcx, [rsp + 48]
	mov	rax, [rsp + 56]
	mov	r8, [rsp + 64]
	add	rsp, 72
	mov	dword [qword lapic + LAPIC_EOI], 0
	iretq


.max = 8
.sz2 = ($-int_shared)

	; must be 16byte aligned

	align 16

	; must be no additional vars after "int_shared + .sz2" and ".handlers"

	.handlers:	  dd 0		; counter, max 8
	.?		  dd 0

.sz = ($-int_shared)+64 ; 64 = 8 byte * 8 handlers that are saved bellow int handler





;===================================================================================================
; need 8byte entries, 4byte addr, 4byte =0 if dev can report if it was its interrupt
;					=1 if dev can't report

					; save offsets from LMode2
;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

	include "int_PF.asm"

;===================================================================================================

  align 8
int_GP:
	jmp	k64err.GP

;===================================================================================================

  align 8
int_DE:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '+' + ('D' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'E' + ('_' shl 16)
	jmp $
	iretq


  align 8
int_DB:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('D' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'B' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_NMI:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('N' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'M' + ('i' shl 16)
	jmp $

	iretq


  align 8
int_BP:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('B' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'P' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_OF:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('O' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'F' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_BR:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('B' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'R' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_UD:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('U' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'D' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_NM:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('N' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'M' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_DF:
	jmp	k64err.DF



  align 8
int_TS:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('T' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'S' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_NP:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('N' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'P' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_SS:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('S' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'S' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_MF:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('M' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'F' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_AC:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('A' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'C' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_MC:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('M' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'C' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_XM:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('X' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'M' + ('_' shl 16)
	jmp $

	iretq

  align 8
int_VE:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('V' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'E' + ('_' shl 16)
	jmp $

	iretq

  align 8
int_dummy1:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'd' + ('u' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'm' + ('1' shl 16)
	jmp $

	iretq


  align 8
int_dummy2:
	mov	dword [qword 120+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'd' + ('u' shl 16)
	mov	dword [qword 124+txtVidMem], (0xcf shl 24) + (0xcf  shl 8) + 'm' + ('2' shl 16)
	jmp $

	iretq

  align 8
int_lapicSpurious:
	iretq

  align 8
int_spurious_pic7:
	iretq

  align 8
int_spurious_pic15:
	iretq

