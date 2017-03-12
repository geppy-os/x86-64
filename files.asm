
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
;     sysFile_load	////////////////////////////////////////////////////////////////////////////
;===================================================================================================
; input:   r8d	file type, =0 if dev driver
;	   r9	pointer to filename

	align 4
sysFile_load:

	stc
	ret

;===================================================================================================
;    sysFile_buildInDrv    /////////////////////////////////////////////////////////////////////////
;===================================================================================================
; Parses drivers that were compiled and loaded together with kernel. Called only once.

	align 4
sysFile_buildInDrv:
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	bts	qword [r14 + 8192 + functions], FN_SYSFILE_BUILDINDRV

	sub	rsp, 256

	mov	rsi, [qword devInfo]
	mov	eax, [rsi + 1*devInfo_sz]
	mov	ecx, [rsi + 12*devInfo_sz]

	mov	[rsp], eax
	mov	[rsp + 4], ecx




	lea	rsi, [basic_devDrivers]
	mov	ebp, basic_devDrivers.cnt
.loop:
	sub	ebp, 1
	jc	.exit

	lea	r8, [rsi + 13]
	mov	eax, [rsi + 9]
	mov	r9d, eax
	call	sysFile_parse
	jc	.next


	lea	r8, [rsi + 13]
	xor	r9, r9
	xor	r12, r12

	mov	rcx, 'PNP0120'
	cmp	[rsi], rcx
	jnz	@f
	mov	r12, rsp
@@:
	call	thread_fromFile
	jc	k64err

.next:
	lea	rsi, [rsi + rax + 13]
	jmp	.loop
.exit:
	add	rsp, 256

	pushf
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	btr	qword [r14 + 8192 + functions], FN_SYSFILE_BUILDINDRV
	popf
	ret

;===================================================================================================
;   sysFile_parse  -  verifies & parses executable/library/dev_driver/...    ///////////////////////
;===================================================================================================
; Prepeare executable/dev_driver for thread_create function.
;				    "thread_create" is not called from this function by any means
;				    "thread_create" is not used for libraries
;---------------------------------------------------------------------------------------------------
; input: r8 - mem pointer to file
;	 r9 - size of the file in bytes
;---------------------------------------------------------------------------------------------------

	align 4
sysFile_parse:
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	bts	qword [r14 + 8192 + functions], FN_SYSFILE_PARSE

	push	rax rcx rdi rsi rbp rbx
	cld


	; decryption skipped (use R9 size here)


	; idea: we can process only exports of ALL files that are known to be loaded
	;	then process imports only

	; or/and we can use dummy functions for all imports that are missing


;===================================================================================================
.hdrSz=0x28				; verify header:

	mov	rax, [r8 + 24]
	xor	ecx, ecx
	mov	[r8], rcx
	mov	[r8 + 8], rcx
	mov	[r8 + 16], rcx

	cmp	al, 0x28
	jb	.err
	mov	byte [r8 + 24], .hdrSz
	shr	rax, 8
	mov	ecx, eax		; ecx = len of init data sect
	shr	rax, 32
	movzx	ebp, ax
	shl	ebp, 12 		; ebp = len of uninit data sec
	shr	eax, 16 		; al  = flags

	mov	rdi, [r8 + 32]
	movzx	ebx, di 		; bx  = exports count
	shr	rdi, 16
	movzx	esi, di 		; si  = imports count
	shr	rdi, 16
	and	edi, 0xfff'ffff 	; edi = file size in bytes, 28bit only
	shl	ebx, 2			; exports *= 4bytes
	shl	esi, 3			; imports *= 8bytes
	cmp	ebx, ecx		; exports must fit into initialized data
	ja	.err

	sub	edi, ecx
	sub	edi, esi
	sub	edi, .hdrSz
	cmp	edi, 0			; edi = code size
	jle    .err

	lea    rcx, [rcx + rsi + .hdrSz]
	mov    qword [r8], rcx	       ; save where code begins
	mov    dword [r8 + 8], edi     ; save code size
	mov    dword [r8 + 12], "_OK_"
;---------------------------------------------------------------------------------------------------


	cld
	shr	esi, 3
	mov	r13d, esi		      ; # of imports
	lea	rsi, [r8 + .hdrSz]	      ; where import section begins

	; TODO: need to check mem boundaries on every mem ptr advancement

.next_import:
	sub	r13d, 1
	jc	.ok

	lodsq					; return: rax[63:32]=func_id, rax[31:0]=lib_id

;===================================================================================================
; parse 1st section	     find library ID and its base addr in memory
;			       (or maybe we need to load file from disk)

	xor	ebp, ebp
	lea	r14, [kExports_libIDs]
	mov	ecx, 8
	not	ebp				; less code size for -1 value
@@:	movsx	edi, word [r14]
	add	ebp, 1				; current id ++
	mov	ebx, edi
	cmp	edi, 0				; check size, 0(file loaded) or string size(still on disk)
	cmovz	edi, ecx
	jl	.import_failed			; terminating size <0, libID not found
	cmp	eax, ebp			;    (TODO: search on disk for a file? need file name)
	jz	.libID_found
	lea	r14, [r14 + rdi + 2]
	jmp	@b

	; INPUT:
	; ebx	= either 0	   OR  string size
	; r14+2 = 8byte base addr  OR  string where library located on disk
.libID_found:
	mov	r14, [r14+2]			; R14 - base address where function offsets are added
	test	ebx, ebx
	jnz	.err				; file still on disk, we don't handle this right now

;===================================================================================================
; parse 2nd section	     find function ID for corresponding library

	lea	rdi, [kExports_func]
	mov	rbp, rax			; eax = library id
	shr	rbp, 32 			; ebp = function id

	movzx	r12d, word [rdi]		; number of libraries(library blocks) available
	add	rdi, 2
	xor	ebx, ebx
.next_lib:
	movzx	ecx, word [rdi] 		; # of functions in this lib_id block
	test	ecx, ecx
	jz	@f
	cmp	ebx, eax
	jz	.find_func
@@:	lea	rdi, [rdi + rcx*4 + 2]
	add	ebx, 1
	sub	r12d, 1
	jnz	.next_lib
	jmp	.import_failed			; jump if can't find funcID in existing library

	; INPUT:
	; word	[rdi]	= number of functions for this lib_id (can be 0)
	; dword [rdi+2] = offset for func #0 (valid only if word[rdi] > 0)
.find_func:
	cmp	[rdi], bp			; check max # of functions available in this lib
	jbe	.import_failed

	mov	eax, [rdi + 2 + rbp*4]		; offset
	add	rax, r14			;	 + base address
	mov	[rsi - 8], rax			; update entry in import section
	jmp	.next_import

;------------------------------------------------
.import_failed:  ; need to provide dummy if import lib+function not found
	jmp	 .err


.ok:	clc
.exit:
	pushf
	lea	r14, [rip]
	shr	r14, 39
	shl	r14, 39
	btr	qword [r14 + 8192 + functions], FN_SYSFILE_PARSE
	popf

	pop	rbx rbp rsi rdi rcx rax
	ret
.err:	stc
	jmp	.exit



