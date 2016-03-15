
; Distributed under GPL v1 License
; All Rights Reserved.


bios_boot:
	cli
	jmp	0:@f
@@:

	xor	eax, eax
	mov	cx, (448*1024)/16
	mov	ds, ax
	mov	ss, ax
	mov	esp, bios_boot
	mov	gs, cx
	mov	[gs:boot_disk], dl
	sti
	;reg	 edx

	; get max PCI bus
	mov	eax, 0xb101
	xor	edi, edi
	int	0x1a
	jc	k16err
	cmp	edx, 0x20494350
	jnz	k16err
	test	al, 10b
	jnz	k16err
	sti
	mov	[gs:max_pci_bus], cl
	;reg	 ecx

	; get EBDA mem
	mov	dword [gs:ebda_mem], 639*1024

;===================================================================================================
	push	gs gs
	pop	ds es
	mov	edi, memMap
	xor	ax, ax
	mov	byte [memMap_szFailed], al
	mov	byte [memMap_cnt], al
	xor	ebx, ebx
.e820:
	xor	eax, eax
	mov	[di], eax
	mov	[di + 4], eax
	mov	[di + 8], eax
	mov	[di + 12], eax
	mov	[di + 16], eax
	sti
	mov	eax, 0xe820
	mov	edx, 0x534d4150
	mov	ecx, 20
	int	0x15
	jc	.e820_done
	cmp	eax, 0x534d4150
	jnz	.e820_done
	cmp	ecx, 20
	jae	@f
.e820_badSize:
	add	byte [memMap_szFailed], 1
	jmp	.e820
@@:
	mov	eax, [di]
	mov	ebp, [di + 4]
	mov	edx, [di + 8]
	mov	ecx, [di + 16]

	cmp	edx, 4096		; if weird size (TODO: test 64bit value)
	jb	.e820_badSize

	shr	ebp, 14 		; need starting address bellow 64TB
	jnz	.e820
	cmp	ecx, 254
	ja	.e820
	mov	[di + 7], cl		; change locaion of mem type

	;mov	 ebp, [di + 4]
	;reg	 ebp
	;sub	 [cs:reg16.cursor],2
	;reg	 eax
	;mov	 ecx, [di + 12]
	;reg	 ecx
	;sub	 [cs:reg16.cursor],2
	;reg	 edx
	;add	 [cs:reg16.cursor],2

	add	byte [memMap_cnt], 1
	add	di, 16
	cmp	byte [memMap_cnt], 63
	ja	.e820_done
	test	ebx, ebx
	jnz	.e820

.e820_done:
	cmp	byte [memMap_cnt], 3
	jb	@f
	;cmp	 [memMap_flags],
	jmp	.memMap_done
@@:
	sti
	xor	cx, cx
	xor	dx, dx
	mov	ax, 0xE801
	int	0x15
	jc	k16err
	jcxz	@f
	mov	ax, cx
	mov	bx, dx
@@:
	movzx	eax, ax
	movzx	ebx, bx
	shl	eax, 10
	shl	ebx, 16
	cmp	eax, 0xF00000
	ja	k16err

	xor	ecx, ecx
	mov	dword [di], 0x1'00000
	mov	dword [di + 4], ecx
	mov	dword [di + 8], eax
	mov	dword [di + 12], ecx
	mov	dword [di + 16], 0x10'00000
	mov	dword [di + 20], ecx
	mov	dword [di + 24], ebx
	mov	dword [di + 28], ecx
	mov	byte [memMap_cnt], 2

.memMap_done:
	sti

;===================================================================================================
	mov	eax, 0x2402
	int	0x15
	jc	@f
	cmp	ax, 1
	jz	.a20_done
@@:
	mov	eax, 0x2401
	int	0x15
	jc	@f
	test	ah, ah
	jz	.a20_done
@@:
	mov	eax, 0x2403
	int	0x15
	jc	.a20_kbd
	test	bx, 10b
	jnz	.a20_fast

.a20_kbd:
	jmp	.a20_fast
	jmp	.a20_done

.a20_fast:
	in	al, 0x92
	bts	ax, 1
	jc	.a20_done
	and	al, 0xFE
	out	0x92, al

.a20_done:
	sti

;=============================================================================== scan PCI bus ======

;pci_initialScan

;===================================================================================================

	mov	ax, 0x4f00
	xor	cx, cx
	mov	es, cx
	mov	di, vbe_temp
	mov	dword [es:di], 'VBE2'
	push	gs
	pop	ds
	int	0x10
	cmp	ax, 0x4f
	jnz	k16err
	cmp	dword [es:di], 'VESA'
	jnz	k16err

	mov	ecx, [es:di + 0xA]		; capabilities
	mov	esi, [es:di + 0xE]		; segment(high word in register) : offset(low word)
	movzx	edx, word [es:di + 0x12]	; total vid mem available in 64KB units
	shl	edx, 16
	mov	[gs:vbeMem], edx
	mov	[gs:vbeCap], ecx

	mov	ebx, esi
	movzx	eax, si 			; eax = offset
	shr	esi, 16
	shr	ebx, 16 			; ebx = segment
	shl	esi, 4
	add	esi, eax

	cmp	esi, 512*1024
	jae	@f
	cmp	esi, bios_boot
	ja	k16err
;---------------------------------------------------------------------------------------------------
@@:
	lea	esi, [eax-2]
	mov	fs, bx
	push	gs
	pop	ds

.vbeModes:
	add	si, 2
	jc	.vbeModes_done
	mov	cx, [fs:si]
	cmp	cx, -1
	jz	.vbeModes_done

	mov	di, vbe_temp2
	push	gs
	pop	es
	mov	dword [es:di + 0x12], 0
	mov	dword [es:di + 0x19], 0
	bts	cx, 14				; set LFB bit
	mov	ax, 0x4f01
	int	0x10
	cmp	ax, 0x4f
	jnz	.vbeModes

	mov	dx, [es:di + 0x10]		; bytes per scanline
	mov	ax, [es:di + 0x12]		; width
	mov	cx, [es:di + 0x14]		; height
	mov	bl, [es:di + 0x19]		; bits per pixel
	mov	bh, [es:di + 0x1b]		; color model
	mov	ebp, [es:di + 0x28]		; LFB

	cmp	bl, 32
	ja	.vbeModes
	cmp	ax, 768
	jb	.vbeModes
	cmp	cx, 768
	jb	.vbeModes
	cmp	bl, 16
	jb	.vbeModes
	cmp	bh, 6				; direct color
	jz	@f
	cmp	bh, 4				; packed pixel
	jnz	.vbeModes
@@:
	movzx	edi, byte [vidModes_cnt]
	add	byte [vidModes_cnt], 1
	imul	edi, sizeof.VBE

	;add	 [cs:reg16.cursor], 4
	;reg	 eax
	;reg	 ecx
	;reg	 ebx

	mov	[vidModes + di + VBE.width], ax
	mov	[vidModes + di + VBE.height], cx
	mov	[vidModes + di + VBE.lfb], ebp
	mov	[vidModes + di + VBE.bps], dx
	mov	[vidModes + di + VBE.bpp], bl
	mov	[vidModes + di + VBE.clrMode], bh
	mov	ax, [fs:si]
	bts	ax, 14
	mov	[vidModes + di + VBE.modeNumber], ax

	cmp	byte [vidModes_cnt], 126	; limit must be positive 1byte number
	jb	.vbeModes


.vbeModes_done:
	movzx	eax, byte [vidModes_cnt]
	reg	eax

	jmp	.vid_setMode

;---------------------------------------------------------------------------------------------------

	mov	byte [vidModes_sel], 4

.vid_table_entry_2:

	movzx	ax, byte [vidModes_cnt] 	; TODO: 0 video modes ????
	sub	ax, 1
	;jc	 .....
	cmp	byte [vidModes_sel], 0
	jge	@f
	mov	byte [vidModes_sel], 0
@@:	cmp	byte [vidModes_sel], al
	jl	@f
	mov	[vidModes_sel], al
@@:
	mov	ax, 3
	int	0x10

	mov	dx, -1
	mov	bx, 16+(80*10)
	push	0xb800
	pop	es
	push	dword 0x4f004f00

.vid_table_entry:
	inc	dx
	cmp	[vidModes_cnt], dx
	jbe	.vid_waitForKey

	mov	si, dx
	imul	si, sizeof.VBE
	add	si, vidModes

	mov	eax, (0xf shl 24) + (0xf shl 8)
	cmp	[vidModes_sel], dl
	jnz	@f
	or	eax, [esp]
@@:	mov	dword [es:bx-10], eax
	mov	dword [es:bx-6], eax
	mov	dword [es:bx-2], eax
	mov	dword [es:bx+2], eax
	mov	dword [es:bx+6], eax
	mov	dword [es:bx+10], eax

	or	word [es:bx+4], 'x'+(0xf shl 8)

	mov	di, bx
	push	word [esp]
	push	[si + VBE.width]
	call	.toAsciiDec

	lea	di, [bx+18]
	push	word [esp]
	push	[si + VBE.height]
	call	.toAsciiDec

	shl	bp, 1
	lea	edi, [bx + 18]
	sub	di, bp
	xor	ecx, ecx
.copyHeight:
	mov	ax, [es:di]
	mov	word [es:ebx + 6 + ecx], ax
	add	cx, 2
	add	di, 2
	cmp	cx, bp
	jbe	.copyHeight

	mov	eax, (0xf shl 24) + (' ' shl 16) + (0xf shl 8) + ' '
	cmp	[vidModes_sel], dl
	jnz	@f
	or	eax, [esp]
@@:	mov	[es:ebx + 6 + ecx], eax
	mov	[es:ebx + 10 + ecx], eax
	mov	[es:ebx + 14 + ecx], eax
	mov	[es:ebx + 18 + ecx], eax
	or	byte [es:bx+20], 'x'

	lea	di, [bx+26]
	movzx	ax, [si + VBE.bpp]
	push	word [esp]
	push	ax
	call	.toAsciiDec

	add	bx, 160
	jmp	.vid_table_entry

.vid_waitForKey:
	add	sp, 4

	xor	ax, ax
	int	0x16


	cmp	ah, 0x48		; up arrow
	jnz	@f
	sub	byte [vidModes_sel], 1
	jmp	.vid_table_entry_2
@@:
	cmp	ah, 0x50		; down
	jnz	@f
	add	byte [vidModes_sel], 1
	jmp	.vid_table_entry_2
@@:
	cmp	ah, 0x1c		; enter
	jz	.vid_setMode
	cmp	ah, 0x01		; ESC
	jz	.vid_setMode
	jmp	.vid_waitForKey

.vid_setMode:

	mov	ax, 3
	int	0x10



;	 mov	 al,10001b		 ; begin PIC 1 initialization
;	 out	 0x20, al
;	 mov	 al,10001b		 ; begin PIC 2 initialization
;	 out	 0xa0, al
;
;	 mov	 al, 80h		 ; IRQ 0-7: interrupts 80h-87h
;	 out	 21h, al
;	 mov	 al, 88h		 ; IRQ 8-15: interrupts 88h-8Fh
;	 out	 0A1h, al
;
;	 mov	 al, 100b		 ; slave connected to IRQ2
;	 out	 0x21, al
;	 mov	 al, 2
;	 out	 0xA1, al
;
;	 mov	 al, 1			 ;EOI
;	 out	 0x21, al
;	 out	 0xA1, al


	; set timer to one-shot mode
	cli
	xor	eax, eax
	cpuid
	mov	al, 10'001'0b		; binary, one-shot, MSB only
	out	0x43, al
	xor	ax, ax
	out	0x40, al		; MSB value
	xor	eax, eax
	cpuid
	sti				; wait for pending ints to go thru

	; measure TSC granularity
	xor	si, si
	mov	bp, 8
	call	.tsc_calibration

	; disable PIC ints
	cli
	mov	al, 255
	out	0xa1, al
	out	0x21, al
	sti

	; wait again for pending ints to go thru
	mov	si, 8
	mov	bp, 8
	call	.tsc_calibration

	; switch to Protected mode
	pushd	0 0 0
	lidt	[ss:esp]
	popfd
	lgdt	[cs:GDTR_RMode]
	mov	eax, cr0
	or	eax, 1
	mov	cr0, eax
	jmp	8:PMode


;===================================================================================================
.tsc_calibration:
	rdtsc
@@:	and	eax, 7
	cpuid
	rdtsc
	mov	[gs:tscBits + si], al
	inc	si
	dec	bp
	jnz	@b
	ret

;===================================================================================================
.toAsciiDec:
	push	bx ax dx cx 10
	mov	cx, [esp + 12]
	mov	bx, [esp + 14]
	pushfd
	std
	xor	bp, bp		; BP - how many digits
	cmp	[vidModes_sel], dl
	jz	@f
	mov	bh, 0xf
@@:
	mov	ax, cx
	xor	dx, dx
	div	word [esp + 4]
	mov	cx, ax
	mov	al, dl
	add	al, 48
	mov	ah, bh
	stosw
	inc	bp
	test	cx, cx
	jnz	@b

	popfd
	pop	dx cx dx ax bx
	ret	4

;===================================================================================================
k16err:
@@:
	hlt
	jmp	@b

;===================================================================================================
reg16:
	pushfd
	pushd	edx
	push	bx ax di es 0xb800
	pop	es

	mov	di, [cs:.cursor]
	add	[cs:.cursor], 18

	mov	edx, [esp+18]
	mov	bx, 8
	mov	ah, 0xE
	cld
.loop:
	rol	edx, 4
	mov	al, dl
	and	al, 15
	cmp	al, 10
	jb	@f
	add	al, 7
@@:	add	al, 48
	stosw
	dec	bx
	jnz	.loop

	pop	es di ax bx
	popd	edx
	popfd
	ret 4

.cursor dw 160

;---------------------------------------------------------------------------------------------------
GDTR_RMode:
	dw GDT_RMode.limit
GDT_RMode:
	dq GDT_RMode
	db -1, -1, 0, 0, 0, 0x9a, 1100'1111b, 0        ; code, ring0, PMode
	db -1, -1, 0, 0, 0, 0x92, 1100'1111b, 0        ; data, ring0 PMode
	dw 0FFFFh,0,9A00h,0AFh		    ; 64-bit code desciptor

  .limit = $-GDT_RMode-1

