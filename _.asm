	use16
	org 0x7c00

MBR:
	push	0xb800
	pop	ds
	mov	dword [0], 0x0404'0404
	mov	dword [4], 0x0404'0404
	mov	dword [8], 0x0404'0404
	mov	dword [12], 0x0404'0404
	mov	dword [16], 0x0404'0404
	mov	dword [20], 0x0404'0404
	mov	dword [24], 0x0404'0404

	jmp	$