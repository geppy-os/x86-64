
; input: r8 = linear addr

	align 8
thread_create:

	ret
		; need per thread stack for alloc4k_ram

sleep:
	ret


;===================================================================================================
; can not use CLI instruction until resumeThreadSw is called

	align 8
noThreadSw:
	pushf
	or	word [lapicT_flags], 4
	popf
	ret


;===================================================================================================
; can not use CLI instruction until resumeThreadSw is called

	align 8
resumeThreadSw:
	pushf
	and	dword [lapicT_flags], not 4	; disable request to stop thread switch
	test	dword [lapicT_flags], 8 	; precache the cacheline (2 mem acceses)
	mfence					; wait before next memory operation
	push	rax rcx
	mov	eax, 2				; disable low priority ints for a short time
	mov	cr8, rax
	mov	ecx, [lapicT_flags]
	xor	eax, eax			; re-enable ALL (default) ints
	mov	cr8, rax

	; if this flag is set by lapicT then we won't enter the lapicT handler anymore unless
	; we trigger lapicT handler manually
	test	ecx, 8
	jz	@f
	int	0x20				; <<<<< don't need EOI <<<<< (bit3 at lapicT_flags)
@@:
	pop	rcx rax
	popf
	ret
