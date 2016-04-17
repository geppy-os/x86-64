
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


;===================================================================================================
; return: r8 - 2byte random value

	align 8
rand_tsc:
	push	rax rdx rcx rsi
	rdtsc
	mov	esi, edx
	ror	eax, 8
	mov	ecx, eax
	shrd	eax, esi, 4
	shr	esi, 4
	and	ecx, 15
	ror	ax, cl
	mov	ecx, eax
	shr	ecx, 16
	mul	cx
	mov	esi, edx
	xor	eax, esi
	movzx	r8d, ax
	pop	rsi rcx rdx rax
	ret