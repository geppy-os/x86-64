
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


g2d_drawText:
	bt	eax, 5
	jnc	.two_directions

	; AL[7] AL[6] AL[5]
	;    1	   0	 1  dn
	;    0	   0	 1  up
	;    1	   1	 1  left
	;    0	   1	 1  right

	movsx	ecx, al 	; sign extend bit 7
	shr	ecx, 8
	or	ecx, 1		; if was -1 then remained -1, if was 0 then became 1
	bt	eax, 6
	jc	.horiz
	add	di, cx		; y +- 1
	jmp	@f
.horiz: add	bx, cx		; x +- 1
	jmp	@f

.two_directions:

	; AL[7] AL[6] AL[5]
	;    1	   0	 0  dn,left
	;    0	   0	 0  up,left
	;    1	   1	 0  dn,right
	;    0	   1	 0  up,right

	movsx	ecx, al 	; sign extend bit 7 (vertical direction)
	rol	eax, 1
	shr	ecx, 8
	movsx	esi, al 	; sign extend bit 6 (horizontal direction)
	shr	esi, 8
	or	ecx, 1
	or	esi, 1
	add	di, cx		; y +- 1
	add	bx, si		; x +- 1
@@: