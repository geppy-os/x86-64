
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	use32
	align 4
PMode:
	mov	eax, 0x10
	mov	ss, ax
	mov	ds, ax
	mov	es, ax
	mov	fs, ax
	mov	gs, ax

;===================================================================================================

					 ;  UC	 UC-  WT   WB
	mov	eax, 1			 ; 000	 111  100  110
	cpuid		; 1fcbfbff	    00	 07   04  06
	bt	edx, 16
	setc	byte [feature_PAT]	; tested on Intel CPU only

	mov	eax, 0x80000000
	cpuid
	cmp	eax, 0x80000008
	jb	k32err.no_longMode

	;intel section 4.1.4	  Enumeration of Paging Features by CPUID

	;----------------------------------------------------
	cmp	byte [feature_PAT], 1
	jnz	.PAT_done

	mov	ecx, IA32_PAT
	rdmsr
	reg	eax, 80c
	reg	edx, 80a


;00H Uncacheable (UC)
;01H Write Combining (WC)
;02H Reserved*
;03H Reserved*
;04H Write Through (WT)
;05H Write Protected (WP)
;06H Write Back (WB)
;07H Uncached (UC-)




.PAT_done:
       ;jmp	$

;===================================================================================================

	mov	eax, cr0
	;		   CD		 NW	 AM(align off)	EM(run MMX)
	and	eax, not((1 shl 30) + (1 shl 29) + (1 shl 18) + (1 shl 2))
	mov	cr0, eax
	mov	eax, cr4
	;	       sse	 xsave
	or	eax, 1 shl 9 ;+ 1 shl 18
	mov	cr4, eax

;============================================================================ Find ACPI RSDT =======

	mov	esi, 0xE0000-16 	; starting address for the search
	mov	ebp, 0x100000-34	; ending address
.find_RSDP:
	add	esi, 16
	cmp	dword [esi], 'RSD '
	jz	.found_RSDT
@@:	cmp	esi, ebp
	jb	.find_RSDP

	cmp	esi, 0xE0000
	jb	.RSDT_found		; RSDT doesn't exist at this point

	mov	esi, [ebda_mem + rmData]
	lea	ebp, [esi + 1024-34]
	sub	esi, 16
	jmp	.find_RSDP
.found_RSDT:
	cmp	dword [esi + 4], 'PTR '
	jnz	@b

	; RSDP checksum
	mov	edi, esi
	mov	edx, 20
	xor	eax, eax
@@:	add	al, [edi]
	add	edi, 1
	sub	edx, 1
	jz	@f
	jmp	@b
@@:	test	eax, eax
	jnz	.find_RSDP

	mov	edi, [esi + 16] 	; rsdt address
	mov	edx, [edi + 4]		; rsdt length
	mov	ecx, edi
	mov	ebx, edx
	test	edi, edi
	jz	.find_RSDP
	cmp	edx, 40
	jl	.find_RSDP

	; RSDT checksum
	xor	eax, eax
@@:	add	al, [edi]
	add	edi, 1
	sub	edx, 1
	jz	@f
	jmp	@b
@@:	test	eax, eax
	jnz	.find_RSDP

	;reg	 ecx, 874
	;reg	 ebx, 874
	mov	[acpi_rsdt + rmData], ecx
	mov	[acpi_rsdt_len + rmData], ebx

.RSDT_found:

;============================================================================== Find MP Table ======

	mov	esi, 0xE0000-16 	; starting address for the search
	mov	ebp, 0x100000-34	; ending address
.find_MP_FPS:
	add	esi, 16
	cmp	dword [esi], '_MP_'
	jz	@f
	cmp	esi, ebp
	jb	.find_MP_FPS

	cmp	esi, 0xE0000
	jb	.MP_found		; MP doesn't exist at all

	mov	esi, [ebda_mem + rmData]
	lea	ebp, [esi + 1024-34]
	sub	esi, 16
	jmp	.find_MP_FPS
@@:
	;-----------------------------------------------
	; checksum for "MP Floating Pointer Structure"

	mov	ebx, [esi + 4]		; address of "MP Table"
	cmp	byte [esi + 8], 1
	jnz	.MP_found
	cmp	byte [esi + 11], 0
	jnz	.MP_found		; some default config present - not interested

	mov	edi, esi
	mov	edx, 16
	xor	eax, eax
@@:	add	al, [edi]
	add	edi, 1
	sub	edx, 1
	jz	@f
	jmp	@b
@@:	test	eax, eax
	jnz	.find_MP_FPS

	; examine MP Config Header

	test	ebx, ebx
	jz	.MP_found
	movzx	ecx, word [ebx + 4]
	cmp	dword [ebx], 'PCMP'
	jnz	.MP_found
	cmp	ecx, 64
	jb	.MP_found

	;reg	 ebx, 875h
	;reg	 ecx, 475h
	mov	[mp_table + rmData], ebx
	mov	[mp_table_len + rmData], ecx
.MP_found:

;===================================================================== Find select ACPI tables =====

	mov	esi, [acpi_rsdt + rmData]
	mov	ebp, [acpi_rsdt_len  + rmData]
	test	esi, esi
	jz	.ACPI_done
	sub	ebp, 36
	jbe	.ACPI_done
	and	ebp, not 3
	jz	.ACPI_done


.ACPI_enumerate:
	add	esi, 4
	mov	edi, [esi + 36-4]
	sub	ebp, 4
	jc	.ACPI_done

	mov	eax, [edi]
	mov	edx, [edi + 4]
	cmp	edx, 36
	jb	.ACPI_enumerate

	cmp	eax, 'SSDT'
	jz	.acpi_ssdt
	cmp	eax, 'APIC'
	jz	.acpi_apic
	cmp	eax, 'MCFG'
	jz	.acpi_mcfg
	cmp	eax, 'FACP'
	jz	.acpi_facp
	cmp	eax, 'HPET'
	jz	.acpi_hpet
	jmp	.ACPI_enumerate

  align 4
.acpi_ssdt:
	cmp	dword [acpi_ssdt_cnt + rmData], 32
	jae	.ACPI_enumerate

	call	.acpi_checksum
	jnz	.ACPI_enumerate

	mov	ecx, [acpi_ssdt_cnt + rmData]
	add	dword [acpi_ssdt_cnt + rmData], 1
	mov	dword [acpi_ssdt + rmData + ecx*4], edi
	mov	dword [acpi_ssdt_len + rmData + ecx*4], edx
	jmp	.ACPI_enumerate

  align 4
.acpi_apic:
	call	.acpi_checksum
	jnz	.ACPI_enumerate

	mov	dword [acpi_apic + rmData], edi
	mov	dword [acpi_apic_len + rmData], edx
	jmp	.ACPI_enumerate

  align 4
.acpi_mcfg:
	call	.acpi_checksum
	jnz	.ACPI_enumerate
	mov	dword [acpi_mcfg + rmData], edi
	mov	dword [acpi_mcfg_len + rmData], edx
	jmp	.ACPI_enumerate

.acpi_facp:
	call	.acpi_checksum
	jnz	.ACPI_enumerate
	mov	dword [acpi_facp + rmData], edi
	mov	dword [acpi_facp_len + rmData], edx

	; DSDT is inside FADT(FACP)

	mov	edi, [edi + 40]
	mov	edx, [edi + 4]
	cmp	dword [edi], 'DSDT'
	jnz	.ACPI_enumerate
	cmp	edx, 64
	jb	.ACPI_enumerate

	call	.acpi_checksum
	jnz	.ACPI_enumerate
	mov	dword [acpi_dsdt + rmData], edi
	mov	dword [acpi_dsdt_len + rmData], edx
	jmp	.ACPI_enumerate

.acpi_hpet:
	call	.acpi_checksum
	jnz	.ACPI_enumerate
	mov	dword [acpi_hpet + rmData], edi
	mov	dword [acpi_hpet_len + rmData], edx
	jmp	.ACPI_enumerate

  align 4
.acpi_checksum:
	push	edx
	mov	ebx, edi
	xor	ecx, ecx
@@:	add	cl, [ebx]
	add	ebx, 1
	dec	edx
	jnz	@b
	pop	edx
	test	ecx, ecx
	ret

.ACPI_done:

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

macro ___debug_showMem1{
	pusha
	pushf
	movzx	ebp, byte [memMap_cnt + rmData]
	mov	esi, memMap + rmData
@@:
	sub	ebp, 1
	jc	@f
	mov	eax, [esi]
	mov	ecx, [esi+4]
	mov	edx, [esi+8]
	mov	ebx, [esi+12]
	add	esi, 16

	cmp	byte [esi-16+7], 1	; FILTER: only mem type = 1 = useble
	;jnz	 @b

	reg	ecx, 84a
	sub	[reg32.cursor], 2
	reg	eax, 84a
	reg	ebx, 84a
	sub	[reg32.cursor], 2
	reg	edx, 84a
	add	[reg32.cursor], 2

	jmp	@b
@@:
	add	[reg32.cursor], 8
	popf
	popa
}

macro ___debug_showMem2{
	pusha
	pushf
	movzx	ebp, byte [memMap_cnt + rmData]
	mov	esi, memMap + rmData
@@:
	sub	ebp, 1
	jc	@f
	mov	eax, [esi]
	mov	edx, [esi+8]
	add	esi, 16

	cmp	byte [esi-16+7], 1
	jnz	@b

	;bswap	 ecx
	;reg	 ecx, 214
	reg	eax, 814
	reg	edx, 814
	add	[reg32.cursor], 2
	jmp	@b
@@:
	add	[reg32.cursor], 6
	popf
	popa
}

;===================================================================================================
;   sort starting mem addresses     ////////////////////////////////////////////////////////////////
;===================================================================================================

	movzx	ebp, byte [memMap_cnt + rmData]
	mov	esi, memMap + rmData
	xor	edi, edi
	sub	ebp, 1
	jc	k32err.1
	jz	.sort_done
	movd	mm7, ebp

.sort_startMemAddr:
	mov	ecx, [esi + 4]
	mov	eax, [esi + 20]
	and	ecx, 0xffffff		; remove mem type byte
	and	eax, 0xffffff

	cmp	ecx, eax
	jb	.sort_next
	ja	.sort_swap

	mov	eax, [esi + 16]
	cmp	[esi], eax
	jbe	.sort_next

.sort_swap:
	movdqa	xmm0, [esi]
	movdqa	xmm1, [esi + 16]
	or	edi, 1
	movdqa	[esi], xmm1
	movdqa	[esi + 16], xmm0

.sort_next:
	add	esi, 16
	sub	ebp, 1
	jnz	.sort_startMemAddr

	test	edi, edi
	jz	.sort_done

	mov	esi, memMap + rmData
	movd	ebp, mm7
	xor	edi, edi
	jmp	.sort_startMemAddr
.sort_done:
	; TODO: check so that one mem entry doesn't overlap with the other mem entry
	; TODO: disable 1st MB of RAM

;===================================================================================================
;  Round starting mem addrs and sizes to 16KB, ranges that are above 64TB are labled invalid =0xff
;  Truncate sizes so that range+size doesn't overlap over 64TB
;  We'll end up with 4byte indexes for both addrs & size, each index represents 16KB
;  We only touch "useable" mem ranges with mem type of 1
;---------------------------------------------------------------------------------------------------

	movzx	ebp, byte [memMap_cnt + rmData]
	mov	esi, memMap + rmData
	cmp	ebp, 1
	jl	k32err.2

	movq	xmm2, [_pmode_noMemType]
	movq	xmm3, [_pmode_almost16kb]
	movq	xmm5, [_pmode_not16kb]

.round_mem:
	movq	xmm0, [esi]
	movq	xmm1, [esi + 8]
	cmp	byte [esi + 7], 1
	jnz	.round_next

	cmp	byte [esi + 15], 0	; unrealistic large size (needs more calculations)
	jnz	.range_invalid

	cmp	dword [esi + 12], 0	; range is invalid if size < 128KB (needs more calculations)
	jnz	@f
	cmp	dword [esi + 8], 128*1024
	jb	.range_invalid
@@:
	pand	xmm0, xmm2		; remove "mem type" byte
	movq	xmm4, xmm0		; save original addr	     XXM0
	paddq	xmm0, xmm3		; += 16383		 (64TB - 1b) + 16383 = 64TB start
	pand	xmm0, xmm5		; and -16384
	movq	xmm6, xmm0		; copy of brand new starting address
	psubq	xmm0, xmm4		; new addr -= old address
	psubq	xmm1, xmm0		; size -= difference betw the 2 addresses
	psrlq	xmm1, 14		; convert (round down) size to 16KB units
	psrlq	xmm6, 14		; convert staring addr to 16KB units
	movq	[esi], xmm6
	movq	[esi + 8], xmm1

	cmp	dword [esi + 4], 0	; starting addr too large ?
	jnz	.range_invalid
	mov	dword [esi + 4], 1 shl 24  ; restore mem type of 1

	; TODO: check 4b addr(in 16KB units) + 8b size (in 16kb units)

	jmp	.round_next

.range_invalid:
	mov	byte [esi + 7], 255
.round_next:
	add	esi, 16
	sub	ebp, 1
	jnz	.round_mem

.round_done:
	;___debug_showMem2
	;___debug_showMem1

;=============================================== split memory into entries bellow 4GB and above ====

	; TODO: rewrite and move this code before sorting

	movzx	ebp, byte [memMap_cnt + rmData]
	cmp	ebp, 1
	jb	k32err.3
	mov	esi, memMap + rmData
	mov	edx, 1

.mem_split:
	mov	eax, [esi]
	mov	ecx, [esi + 8]
	cmp	byte [esi + 7], 1		; useable RAM only !!!
	jnz	@f

	mov	ebx, eax
	mov	edi, 0x40000
	add	ebx, ecx
	jc	k32err.4			; little sanity check
	cmp	eax, edi
	jae	@f				; exit if starting addr >= 4gb
	cmp	ebx, edi
	jbe	@f				; exit if ending addr <= 4GB

	sub	edx, 1				; only one entry that splits 4GB region can exist
	jnz	k32err.5

	sub	edi, eax			; size for current entry
	sub	ecx, edi			; size for new entry
	movzx	eax, byte [memMap_cnt + rmData]
	cmp	eax, 63
	jae	@f

	shl	eax, 4
	add	eax, memMap + rmData
	add	byte [memMap_cnt + rmData], 1

	mov	dword [esi + 8], edi
	mov	dword [eax], 0x10000
	mov	dword [eax + 4], 1 shl 24
	mov	dword [eax + 8], ecx
	mov	dword [eax + 12], 0
@@:
	add	esi, 16
	dec	ebp
	jnz	.mem_split

	;___debug_showMem2
	;___debug_showMem1

	; TODO: make separate array for 2MB aligned entries

;=================================================== alloc 2MB bellow 4GB for the kernel code ======

	; go thru entries starting with last (highest mem addr)

.alloc2_2mb:
	movzx	ebp, byte [memMap_cnt + rmData]
	sub	ebp, 1
	jc	k32err.6
	shl	ebp, 4
	lea	esi, [memMap + rmData  + ebp]	; alloc highest physical RAM bellow 4GB

.alloc_2mb:
	mov	eax, [esi]
	mov	ecx, [esi + 8]
	cmp	byte [esi + 7], 1		; useable RAM only
	jnz	.alloc2_next
	cmp	ecx, 0x100			; min 4MB size (we may split it into 2MB and leftover)
	jb	.alloc2_next
	cmp	eax, 0x3fe00			; bellow ~4gb for the starting addr
	ja	.alloc2_next

	lea	ebx, [eax + ecx]		; addr + size
	mov	edx, ebx
	test	ebx, 0x7f			;	is it multiple of 2MB
	jz	.alloc2 			;	if multiple then we chop off 2MB from end addr

	; create new memory entry
	;----------------------------------------------

	and	ebx, not 0x7f			; address for new entry   EBX
	sub	edx, ebx			; end addr - multiple of 2MB addr = size for new entry
	movzx	edi, byte [memMap_cnt + rmData]

	cmp	edi, 63
	jae	@f				; don't create new entry if can't (some mem is lost)

	shl	edi, 4
	mov	dword [memMap + rmData	+ edi], ebx
	mov	dword [memMap + rmData	+ edi+4], 1 shl 24
	mov	dword [memMap + rmData	+ edi+8], edx
	mov	dword [memMap + rmData	+ edi+12], 0
	add	byte [memMap_cnt + rmData], 1
@@:
	sub	ecx, edx
	jbe	k32err.7
	mov	[esi + 8], ecx

	; alloc the 2MB
	;----------------------------------------------
.alloc2:
	add	eax, ecx
	test	eax, 0x7f
	jnz	k32err.c			; end addr must be multiple of 2MB

	cmp	ecx, 0x80			; size must be min 2MB
	jb	k32err.d

	sub	ebx, 0x80			; new entry start addr -= 2MB
	sub	eax, 0x80			; old entry  end  addr -= 2MB
	cmp	ebx, eax
	jnz	k32err.e

	sub	ecx, 0x80
	mov	[esi + 8], ecx
	jnz	.alloc2_done
	mov	byte [esi + 7], 255
	jmp	.alloc2_done

.alloc2_next:
	sub	esi, 16
	sub	ebp, 16
	jnc	.alloc_2mb
	jmp	k32err.9

.alloc2_done:
	movd	xmm7, eax			;					XMM7
	cmp	eax, 0x40000-0x80		; 2MB must start bellow 4GB
	ja	k32err.f

	reg	eax, 80e
	push	0x200000 eax			; size & addr
	call	memTest32
	jnz	.alloc2_2mb

	;___debug_showMem2

	; TODO: alloc a few MBs for LFB framebuffer

;================================================================== alloc several 16KB chunks ======

.16kb_cnt = 8

	movzx	ebp, byte [memMap_cnt + rmData]
	shl	ebp, 4
	lea	esi, [memMap + rmData + ebp - 16]
	xor	edx, edx

.alloc16:
	cmp	edx, .16kb_cnt
	jz	.alloc16_done
	cmp	ebp, 0
	jle	k32err.a

	mov	eax, [esi]
	mov	ecx, [esi + 8]
	cmp	byte [esi + 7], 1
	jnz	.alloc16_switch
	test	ecx, ecx
	jz	k32err.11

	add	eax, ecx
	jc	k32err.10
	cmp	eax, 0x40000
	jae	.alloc16_switch

	sub	eax, 1
	push	16384 eax
	call	memTest32
	jnz	@f

	push	eax
	add	edx, 1
@@:
	sub	ecx, 1
	jc	k32err.b
	mov	[esi + 8], ecx
	jnz	.alloc16

	mov	byte [esi + 7], 255

.alloc16_switch:
	sub	esi, 16
	sub	ebp, 16
	jmp	.alloc16
@@:
.alloc16_done:
	;___debug_showMem2

	movzx	eax, byte [memMap_cnt + rmData]
	mov	[memMap_cnt2 + rmData], eax


;===================================================================================================
; copy 64bit kernel

	movd	ecx, xmm7
	mov	edi, _pmode_ends
	shl	ecx, 14
	mov	esi, _lmode_ends - LMode
@@:	movdqa	xmm0, [edi]
	movdqa	[ecx], xmm0
	add	edi, 16
	add	ecx, 16
	sub	esi, 16
	jge	@b

;===================================================================================================
; setup initial paging
;1)
	shl	dword [esp], 14
	call	zeroMem32
	pop	esi

	mov	cr3, esi			; pml4
	movd	ebx, xmm7			; 2mb in 16kb units
	lea	eax, [esi + 4096   + 7] 	; Present, R/W, User
	lea	ecx, [esi + 4096*2 + 3]
	lea	edi, [esi + 4096*3 + 3]

	shl	ebx, 14
	or	ebx, 0x81			; PageSize=1, Present
	mov	[esi], eax			; PML4		-> PDP-0 (512GB)
	mov	[eax - 7], ecx			; PDP-0 	-> PD-0 (1GB)
	sub	ecx, 3
	mov	[ecx], edi			; PD-0 [0-2mb)	-> PT-0 (2MB)	      EDI
	mov	[ecx + 8], ebx			; PD-1 [2-4mb)	-> kernel code (2MB)
	sub	edi, 3
	or	esi, 3
	mov	[esi + 511*8-3], esi		; last PML4 entry to the same PML4 table

	movd	xmm6, ecx			; PD-0	=  xmm6

	; identity map 1st lowest 512KB (from 0x00000 to 0x7ffff)
	push	ecx edi
	mov	eax, 3
	mov	ecx, 128
@@:	mov	dword [edi], eax
	add	edi,8
	add	eax, 0x1000
	dec	ecx
	jnz	@b
	pop	edi ecx

	; map vbe text mode memory to ZERO linear address :)
	mov	dword [edi     ], 0xb8000 + 10011b
	mov	dword [edi + 8 ], 0xb9000 + 10011b	; with "disable cache" option
	mov	dword [edi + 16], 0xba000 + 10011b
	mov	dword [edi + 24], 0xbc000 + 10011b
	mov	dword [edi + 32], 0xbd000 + 10011b
	mov	dword [edi + 40], 0xbe000 + 10011b
	mov	dword [edi + 48], 0xbf000 + 10011b

;---------------------------------------------------------------------------- map shared data ------
;2)
	shl	dword [esp], 14
	call	zeroMem32
	pop	esi

	; PT-0	from 0x100000 to 0x1fffff (2nd lowest megabyte)
	add	esi, 3
	lea	eax, [esi + 4096]
	lea	ebx, [esi + 4096*2]
	lea	ebp, [esi + 4096*3]
	mov	[edi + 0x1fc * 8], esi		 ; shared data1
	mov	[edi + 0x1fd * 8], eax		 ;	      2
	mov	[edi + 0x1fe * 8], ebx		 ;	      3
	mov	[edi + 0x1ff * 8], ebp		 ; locks

;-------------------------------------------------------------------------------- map VBE LFB ------

;3)
	shl	dword [esp], 14
	call	zeroMem32
	pop	esi
	movd	xmm5, esi

	movzx	eax, byte [vidModes_sel + rmData]
	add	ecx, ((vbeLfb shr (12+9)) and 0x1ff)*8
	cmp	eax, 0xff
	jz	.vbe_is_mapped			; invalid video mode

	imul	eax, sizeof.VBE
	movzx	ebp, [eax + vidModes + rmData + VBE.height]
	movzx	ebx, [eax + vidModes + rmData + VBE.bps]
	mov	edi, [eax + vidModes + rmData + VBE.lfb]
	mov	dword [vbeLfb_ptr + rmData], vbeLfb

	imul	ebp, ebx			; height *= scanline in bytes
	reg	ebp, 80a
	mov	eax, edi
	or	edi, 3 + PG_PCD
	and	eax, 0x1fffff			; if starting addr is 2MB aligned
	jz	.map_vbe_2mb			; then start mapping in 2MB chunks right away
	test	eax, 4095
	jz	.vbe_align_phys_addr
	mov	byte [vidModes_sel + rmData], -1
	jmp	.vbe_is_mapped
	;---------------------------------

.vbe_align_phys_addr:
	; code bellow prior to ".map_vbe_2mb" was not properly tested
	; due to lack of real life cases

	; some woodo magic
	mov	edx, ecx
	mov	ecx, eax
	add	[vbeLfb_ptr + rmData], eax
	neg	eax
	jz	k32err.13
	shr	ecx, 12
	and	eax, 0x1fffff
	mov	ebx, ebp
	xor	esi, esi
	sub	ebp, eax			; total size -= smaller chunk
	cmovc	eax, ebx
	cmovc	ebp, esi			; use smallest size, either EBP or EAX
	shl	ecx, 3

	movd	esi, xmm5
	lea	ebx, [esi + 4096]
	lea	esi, [esi + ecx + 3]
	btr	edi, 7				; remove PG_PS flag
	mov	ecx, edx
	mov	[ecx], esi			; PDe -> PT (covers 2MB)
	add	ecx, 8
	sub	esi, 3
	movd	xmm5, ebx
@@:
	mov	[esi], edi
	add	esi, 8
	add	edi, 4096
	sub	eax, 4096
	jnz	@b

	test	ebp, ebp
	jz	.vbe_is_mapped

	; additional sanity checks
	test	esi, 4095
	jnz	k32err.14
	mov	ebx, edi
	and	edi, not 4095
	test	edi, 0x1fffff
	jnz	k32err.12
	mov	edi, ebx

	;---------------------------------
.map_vbe_2mb:
	sub	ebp, 0x200000
	jc	.map_vbe_leftover		; jump mainly taken for small resoultions
	bts	edi, 7				; set PG_PS
@@:
	mov	[ecx], edi			; PDe -> 2MB page
	add	ecx, 8
	add	edi, 0x200000
	sub	ebp, 0x200000
	jg	@b
	jz	.vbe_is_mapped

.map_vbe_leftover:
	add	ebp, 0x200000
	jz	.vbe_is_mapped
	;---------------------------------

	; process remaining 2MB
	movd	esi, xmm5
	lea	eax, [esi + 4096]
	or	esi, 3
	btr	edi, 7				; remove PG_PS flag
	mov	[ecx], esi			; PDe -> PT (covers 2MB)
	sub	esi, 3
	movd	xmm5, eax
@@:
	mov	[esi], edi
	add	esi, 8
	add	edi, 4096
	sub	ebp, 4096
	jg	@b

.vbe_is_mapped:

;================================================================ map CPU private memory (96KB) ====
; 1st cpu starts at 4MB

	movd	ecx, xmm6			; restore ECX, PD-0
;4)
	shl	dword [esp], 14
	call	zeroMem32
	pop	esi
;5)
	shl	dword [esp], 14
	call	zeroMem32
	pop	edi

	add	esi, 3
	lea	eax, [esi + 4096]
	lea	ebx, [esi + 4096*2]
	lea	ebp, [esi + 4096*3]
	mov	[ecx + 16], esi 		 ; PDe-2 [4-6mb)  -> PageTable (2MB)
	sub	esi, 3
	mov	[esi], eax			 ; idt
	mov	[esi + 8], ebx			 ; stack for some exceptions
	;mov	 [esi + 16]			 ; reserved for "paging_ram"
	mov	[esi + 24], ebp 		 ; some data and "threads"

	add	edi, 3
	lea	eax, [edi + 4096]
	lea	ebx, [edi + 4096*2]
	lea	ebp, [edi + 4096*3]
	;mov	 [esi + 32], edi		; reserved for "pgRam4" 	EDI
	mov	[esi + 40], eax 		; kStack
	mov	[esi + 48], ebx 		; kStack
	;	 [esi + 56]			; unused
	;	 [esi + 64]			; PF_ram. 32KB, 8 entries * 8 byte

	mov	[esi + 128], ebp		; registers
	mov	[esi + 136], edi		; timer registers		EDI

;6)	;----------------------------------------
	shl	dword [esp], 14
	call	zeroMem32
	pop	edi

	add	edi, 3
	lea	eax, [edi + 4096]
	lea	ebx, [edi + 4096*2]
	lea	ebp, [edi + 4096*3]

	mov	[esi + 144], edi		; user_data_rw

;===================================================================================================

	mov	eax, cr4
	or	eax, 1 shl 5		; PAE
	mov	cr4, eax
	mov	ecx,0xc0000080		; EFER MSR
	rdmsr
	or	eax, 1 shl 8		; enable long mode
	wrmsr
	mov	eax, cr0
	or	eax, 1 shl 31
	mov	cr0, eax		; enable paging

	jmp	0x18:0x200000		; jmp 0x18:LMode

	; execution continues to file "kernel64.asm" at "LMode" label


;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

; need to return back to real mode, switch to text nide and display errors
k32err:
.offset = .k32err_len+2

	mov	dword [0xb8000+48], 0x02040204
	mov	dword [0xb8000+52], 0x04040404
	hlt
	jmp	k32err
.1:
	mov	dword [0xb8000+.offset], 0x04310430
	jmp	@f
.2:	mov	dword [0xb8000+.offset], 0x04320430
	jmp	@f
.3:	mov	dword [0xb8000+.offset], 0x04330430
	jmp	@f
.4:	mov	dword [0xb8000+.offset], 0x04340430
	jmp	@f
.5:	mov	dword [0xb8000+.offset], 0x04350430
	jmp	@f
.6:	mov	dword [0xb8000+.offset], 0x04360430
	jmp	@f
.7:	mov	dword [0xb8000+.offset], 0x04370430
	jmp	@f
.8:	mov	dword [0xb8000+.offset], 0x04380430
	jmp	@f
.9:	mov	dword [0xb8000+.offset], 0x04390430
	jmp	@f
.a:	mov	dword [0xb8000+.offset], (4 shl 24) + ('a' shl 16) + (4 shl 8) + '0'
	jmp	@f
.b:	mov	dword [0xb8000+.offset], (4 shl 24) + ('b' shl 16) + (4 shl 8) + '0'
	jmp	@f
.c:	mov	dword [0xb8000+.offset], (4 shl 24) + ('c' shl 16) + (4 shl 8) + '0'
	jmp	@f
.d:	mov	dword [0xb8000+.offset], (4 shl 24) + ('d' shl 16) + (4 shl 8) + '0'
	jmp	@f
.e:	mov	dword [0xb8000+.offset], (4 shl 24) + ('e' shl 16) + (4 shl 8) + '0'
	jmp	@f
.f:	mov	dword [0xb8000+.offset], (4 shl 24) + ('f' shl 16) + (4 shl 8) + '0'
	jmp	@f
.10:	mov	dword [0xb8000+.offset], 0x04000400 + '1' + ('0' shl 16)
	jmp	@f
.11:	mov	dword [0xb8000+.offset], 0x04000400 + '1' + ('1' shl 16)
	jmp	@f
.12:	mov	dword [0xb8000+.offset], 0x04000400 + '1' + ('2' shl 16)
	jmp	@f
.13:	mov	dword [0xb8000+.offset], 0x04000400 + '1' + ('3' shl 16)
	jmp	@f
.14:	mov	dword [0xb8000+.offset], 0x04000400 + '1' + ('4' shl 16)
	jmp	@f
.15:	mov	dword [0xb8000+.offset], 0x04000400 + '1' + ('5' shl 16)
	jmp	@f
@@:
	mov	esi, .k32err
	mov	ecx, .k32err_len/2
	jmp	.display
.no_xsave:
	jmp	@f
.no_osxsave:
	jmp	@f
.no_ssse3:
	jmp	@f
.no_longMode:
@@:
	mov	esi, .minCpuFeatures
	mov	ecx, .minCpuFeatures_len/2
.display:
	cld
	mov	edi, 0xb8000
	rep	movsw
	hlt
	jmp	$

;---------------------------------------------------------------------------------------------------
.k32err: db "G e p p y :   3 2 b i t   e r r o r : "
.k32err_len = $-.k32err
.minCpuFeatures: db "G e p p y :     M i n   C P U   f e a t u r e s   a r e   n o t   m e t ! "
.minCpuFeatures_len = $-.minCpuFeatures

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

	align 4
zeroMem32:
	pushf
	push	edi ecx
	pxor	xmm0, xmm0
	mov	edi, [esp + 16]
	mov	ecx, 16384/128

	align 4
@@:
	movdqa	[edi], xmm0
	movdqa	[edi + 16], xmm0
	movdqa	[edi + 32], xmm0
	movdqa	[edi + 48], xmm0
	movdqa	[edi + 64], xmm0
	movdqa	[edi + 80], xmm0
	movdqa	[edi + 96], xmm0
	movdqa	[edi + 112], xmm0
	add	edi, 128
	dec	ecx
	jnz	@b

	pop	ecx edi
	popf
	ret

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
memTest32:
	push	eax

	; !!! addr comes in 16KB units

	xor	eax, eax
	pop	eax
	ret 8

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================
reg32:

	pushf
	push	edx ebx eax edi

	mov	ebx, [esp + 28]
	mov	edx, 8
	mov	ah, bl
	shr	ebx, 8
	cmp	ebx, edx
	cmova	ebx, edx

	lea	edi, [ebx*2 + 2]
	xadd	[.cursor], edi
	mov	edx, [esp + 24]

	lea	edi, [edi + ebx*2 + 0xb8000-2]
	std
.loop:
	mov	al, dl
	and	al, 15
	cmp	al, 10
	jb	@f
	add	al, 7
@@:	add	al, 48
	stosw
	ror	edx, 4
	dec	bx
	jnz	.loop

	pop	edi eax ebx edx
	popf
	ret 8

	align 4
.cursor dd 160 ;0960	; in bytes, 2bytes per symbol in text mode

;===================================================================================================
;///////////////////////////////////////////////////////////////////////////////////////////////////
;===================================================================================================

_pmode_not16kb		dq not 16383
_pmode_almost16kb	dq 16383
_pmode_noMemType	dq 0xff'ffff'ffff'ffff

