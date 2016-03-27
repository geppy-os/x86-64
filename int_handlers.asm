
int_handlers:

	include "int_PF.asm"

;===================================================================================================

  align 8
int_GP:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('G' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'P' + ('_' shl 16)


	mov	eax, [rsp]
	jmp	$

	iretq

;===================================================================================================

  align 8
int_DE:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('D' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'E' + ('_' shl 16)
	jmp $
	iretq


  align 8
int_DB:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('D' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'B' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_NMI:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('N' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'M' + ('i' shl 16)
	jmp $

	iretq


  align 8
int_BP:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('B' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'P' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_OF:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('O' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'F' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_BR:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('B' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'R' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_UD:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('U' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'D' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_NM:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('N' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'M' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_DF:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('D' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'F' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_TS:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('T' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'S' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_NP:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('N' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'P' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_SS:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('S' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'S' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_MF:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('M' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'F' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_AC:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('A' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'C' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_MC:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('M' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'C' + ('_' shl 16)
	jmp $

	iretq


  align 8
int_XM:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('X' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'M' + ('_' shl 16)
	jmp $

	iretq

  align 8
int_VE:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + '_' + ('V' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'E' + ('_' shl 16)
	jmp $

	iretq

  align 8
int_dummy1:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + 'd' + ('U' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'm' + ('1' shl 16)
	jmp $

	iretq


  align 8
int_dummy2:
	mov	dword [qword 120], (0xcf shl 24) + (0xcf  shl 8) + 'd' + ('U' shl 16)
	mov	dword [qword 124], (0xcf shl 24) + (0xcf  shl 8) + 'm' + ('2' shl 16)
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

