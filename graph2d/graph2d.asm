
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	include 'fillRect.asm'


;===================================================================================================
; check if LFB was mapped properly - if not then #PF will trigger
; this also clears sceen to R8 color if sucessfull, or maybe partially if failed
;===================================================================================================
; input:  r8 - color
; return: CF=0 of OK to copy to VBE LFB
;	  CF=1 if don't copy anything to VBE LFB. Or this func can fail with #PF
;---------------------------------------------------------------------------------------------------
; GUI can still run regadless of outcome and with current design it neeed screen refresh timer.

g2d_init_screen:
	movzx	esi, byte [qword vidModes_sel + rmData]
	cmp	esi, 0xff
	jz	.err

	mov	r9, screen
	mov	rax, r8
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



	movzx	edi, [r8 + rsi + VBE.width]
	movzx	eax, [r8 + rsi + VBE.height]
	movzx	esi, [r8 + rsi + VBE.bps]
	movzx	ecx, [r8 + rsi + VBE.bytesPerPx]

	mov	[r9 + DRAWBUFF.width], edi
	mov	[r9 + DRAWBUFF.height], eax
	mov	[r9 + DRAWBUFF.bpl], esi
	mov	[r9 + DRAWBUFF.bpp], ecx

	mov	[r9 + DRAWBUFF.clip.left], 0
	mov	[r9 + DRAWBUFF.clip.top], 0
	mov	[r9 + DRAWBUFF.clip.right], edi
	mov	[r9 + DRAWBUFF.clip.bottom], eax
	mov	[r9 + DRAWBUFF.ptr], r10

	clc
@@:	ret
.err:	stc
	jmp	@b


