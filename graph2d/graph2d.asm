
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	include 'fillSolidRect.asm'
	include 'drawText.asm'
	include 'copyRect.asm'
	include 'cursors.asm'


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================


	align 8
fillSolidRect:
	ret


	align 8
drawText:
	ret


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

; when we get a screen timer, we first flush what we have then send notification to ring3 apps
				   ; if they want such a notification at all
				   ; GAMES: user does something - AI reacts, timers are for movies?

; one buffer for all back windows,
; one buffer for most front window that will have copy of the back wnds where visible
; one LFB screen


; when mouse is

g2d_flush:
	cmp	dword [qword vbeLfb_ptr + rmData], 0
	jz	.exit
	cmp	qword [qword vidBuff + DRAWBUFF.ptr], 0
	jz	.exit

	mov	r8, vidBuff_changes
	mov	[r8 + RECT.left], 0
	mov	[r8 + RECT.top], 0
	mov	[r8 + RECT.right], 600
	mov	[r8 + RECT.bottom], 600

	call	g2d_copyToScreen

.exit:
	ret



;===================================================================================================
; check if LFB was mapped properly - if not then #PF will trigger
; this also clears sceen to R8 color if sucessfull, or maybe partially if failed
;===================================================================================================
; return: CF=0 of OK to use graphics (vidBuff.DRAWBUFF.ptr != 0)
;	  CF=1 if don't mess with graphics. This func can also fail with #PF (vidBuff.DRAWBUFF.ptr=0)
;
;---------------------------------------------------------------------------------------------------
; GUI can still run regadless of outcome and with current design it neeed screen refresh timer.

g2d_init_screen:
	movzx	esi, byte [qword vidModes_sel + rmData]
	cmp	esi, 0xff
	jz	.err

	mov	r9, screen
	mov	rax, r8
	mov	rax, 0xffff00'00ffff00
	mov	r8d, vidModes + rmData

	imul	esi, sizeof.VBE
	movzx	ecx, [r8 + rsi + VBE.bps]
	movzx	edi, [r8 + rsi + VBE.height]

	imul	ecx, edi
	mov	ebp, ecx
	shr	ecx, 3
	mov	edi, [qword vbeLfb_ptr + rmData]
	mov	r10, rdi
	cld
	rep	stosq
	and	ebp, 7
	mov	ecx, ebp
	rep	stosb

	; setup VBE LFB

	movzx	edi, [r8 + rsi + VBE.width]
	movzx	eax, [r8 + rsi + VBE.height]
	movzx	ecx, [r8 + rsi + VBE.bytesPerPx]
	movzx	esi, [r8 + rsi + VBE.bps]		; esi

	mov	[r9 + DRAWBUFF.width], edi
	mov	[r9 + DRAWBUFF.height], eax
	mov	[r9 + DRAWBUFF.bpl], esi
	mov	[r9 + DRAWBUFF.bpp], ecx

	mov	[r9 + DRAWBUFF.clip.left], 0
	mov	[r9 + DRAWBUFF.clip.top], 0
	mov	[r9 + DRAWBUFF.clip.right], edi
	mov	[r9 + DRAWBUFF.clip.bottom], eax
	mov	[r9 + DRAWBUFF.ptr], r10

	; setup DoubleBuffer for VBE LFB (DoubleBuffer line width must be multiple of 4 pixels)

	mov	r8, vidBuff
	mov	[r8 + DRAWBUFF.clip.left], 0
	mov	[r8 + DRAWBUFF.clip.top], 0
	mov	[r8 + DRAWBUFF.clip.right], edi
	mov	[r8 + DRAWBUFF.clip.bottom], eax
	add	edi, 3
	and	edi, not 3
	mov	[r8 + DRAWBUFF.width], edi
	imul	edi, 3
	mov	[r8 + DRAWBUFF.height], eax
	mov	[r8 + DRAWBUFF.bpl], edi
	mov	[r8 + DRAWBUFF.bpp], 3

	mov	rcx, r8

	; alloc mem for the DoubleBuffer (in 4KB chunks unfortunately, and not 2MB)
	imul	edi, eax
	add	edi, 0x1fffff
	and	edi, not 0x1fffff
	shr	edi, 14
	mov	r9d, edi
	mov	rax, 0xc00000/16384
	mov	r8, rax
	shl	rax, 14
	mov	r12d, PG_P + PG_RW + PG_ALLOC
	call	alloc_linAddr
	jc	k64err.allocLinAddr

	mov	[rcx + DRAWBUFF.ptr], rax
	mov	word [qword txtVidCursor + rmData], 10

	clc
@@:	ret
.err:	stc
	jmp	@b




