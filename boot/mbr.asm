	use16
	org 0x7c00

MBR:
	xor	cx, cx
	mov	ds, cx
	mov	si, MBR+(@f-MBR)
	les	di, [si-4]
	mov	ss, cx
	mov	sp, di
	sti
	cld
	mov	cl, (_end-MBR2+1)/2
	rep	movsw
	jmp	0:MBR2

@@:
	org 0x7a00
MBR2:
	mov	fs, dx
	mov	ax, 3
	int	10h

	mov	cl, 4
	mov	si, 0x7c00+0x200-64-2
@@:
	test	byte [si], 0x80
	jnz	@f
	add	si, 16
	dec	cx
	jnz	@b
	jmp	Error
@@:

	xor	ebp, ebp
	mov	ebx, [si+8]

	mov	si, lba
	mov	dword [si+8], ebx
	mov	dword [si+12], ebp

	mov	ah, 0x42
	mov	dx, fs
	int	0x13
	jc	Error


	pushd	0x55556666
	call	reg

	mov	dx, fs
	jmp	0x7c00


	align 4
Error:
	push	0xb800
	pop	ds
	mov	dword [0], 0x04040404
	mov	dword [4], 0x0e040e04
	mov	dword [8], 0x06040604

	jmp	$

;macro sdf{
reg:
	pushfd
	pushd	edx
	push	bx ax di es 0xb800
	pop	es

	mov	di, [cs:.cursor]
	add	[cs:.cursor], 18

	mov	edx, [esp+18]
	mov	bx, 8
	mov	ah, 0xC
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

.cursor dw 80 ;160

;}
	align 4
lba:	dd 0x00010010
	dd 0x7c00
	dd 0xffffffff
_end:
