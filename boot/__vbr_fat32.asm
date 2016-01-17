

    org $7c00
    use16

VBR:
    jmp   short @f
    nop

    bpb_OEM		db 'MSDOS5.0'
    bpb_SectSize	dw 512			; =512, Required
    bpb_SectPerClust	db 0
    bpb_ReservedSect	dw 0
    bpb_FATsCnt 	db 0
    bpb_RootSize	dw 0
    bpb_TotalSect16	dw 0
    bpb_Media		db 0
    bpb_FatSize16	dw 0
    bpb_TrackSect	dw 0
    bpb_Heads		dw 0
    bpb_hiddenSect	dd 0

    bpb_TotalSect	dd 0
    bpb_fatSz		dd 0
    bpb_extFlags	dw 0
    bpb_ver		dw 0
    bpb_rootClust	dd 0


    bpb_FSInfo		dw 0
    bpb_backupBoot	dw 0
			rb 12

    bpb_DriveNum	db 0
    bpb_winSignature	db 0
    bpb_bootSig 	db 0
    bpb_volID		dd 0
    bpb_volLabel	db "NO NAME    "
			db "FAT32   "

    offs	= lbaPacket-VBR
;===================================================================================================
@@:
    xor     ebp, ebp
    mov     fs, dx			; FS[7:0] = drive #
    jmp     0:@f			; flush CS
align 4 				; not really sure what alignment is for, might be for bug--
lbaPacket:  dd $00'01'00'10		; $10 = size of LBA struct;  $01 = # of LBA sectors to read
@@:
    mov     ss, bp
    mov     sp, VBR
    mov     si, lbaPacket		; SI points to LBA packet struct
    mov     ds, bp
    mov     dword [si+12], ebp

    ; check int13 extensions (dl = drive # already)
    mov     ah, $41
    mov     bx, $55aa
    int     $13
    jc	    .no_LBA
    cmp     bx, $aa55
    jnz     .no_LBA
    test    cl, 1
    jnz     .LBA_Legacy_done
.no_LBA:
    jmp     Error
;    not     byte [si]			 ; IF [SI]=$10 then LBA,   IF [SI] != $10 then Legacy
;
;    ; get drive geometry for int13 ah=2
;    mov     dx, fs
;    mov     ah, 8
;    int     $13			 ; return: DH = maxHead-1, CX[5:0] = max sector
;    jc      Error
;    movzx   bp, dh
;    inc     bp 			 ; ebp[31:16] = 0 previously,  ebp[15:0] = 9bit max head
;    and     ecx, 111111b
;===================================================================================================
.LBA_Legacy_done:

    push    ebp 			; save max head at [si-offs-4]
    push    ecx 			; save max sector at [si-offs-8]

    mov     ebx, [si-offs+28]		; ebx = hidden sectors = start of partition
    mov     bp, [si-offs+14]
    add     ebp, ebx			; reserved sectors count += beginning of partition
    push    ebp 			; [si-offs-12] = beginning of FAT in LBA units (512b units)
    mov     ebx, [si-offs+44]		; EBX = root cluster
    bts     ebp, 31			; EBP = index of cached 512b chunk inside FAT (=invalid index)

    ;------------------------------------
fileSearch:
    mov     dword [si+4], $0000'8000	; segment:offset where directory custers(one at a time) copied

copyClusters:
    bsf     cx, [si-offs+13]		; "a step" towards # of 512byte chunks in one cluster
    movzx   eax, byte [si-offs+16]	; read FAT count
    mul     dword [si-offs+36]		; *= FAT size (all in 512b units)
    lea     edx, [ebx-2]		; edx = cluster
    shl     edx, cl			; edx = cluster * secPerCluster
    add     eax, [si-offs-12]		; eax:	FATs size += beginning of FATs
    add     eax, edx			; eax = beginning of specific clusters
    mov     [si+8], eax 		; 4byte LBA
    call    readDisk

.patch2:
    jmp     short @f

@@:
    mov     di, $8000
find_file:
    cmp     dword [di],   "KIWI"
    jnz     @f
    cmp     dword [di+4], "    "
    jnz     @f
    cmp     dword [di+8], "IMG "
    jnz     @f

    push    0
    call    reg



    mov     bx, [di+20] 	     ; top 16bit of cluster
    shl     ebx, 16
    mov     bx, [di+26] 	     ; low 16bit of cluster

    ; patch jumps
    mov     byte [copyClusters.patch2+1], read_FAT_chunk-copyClusters.patch2-2
    mov     byte [read_FAT_chunk.patch1+2], (copyClusters-read_FAT_chunk.patch1-4) and $ff

    jmp     fileSearch
@@:
    add     di, 32
    cmp     di, [si+4]
    jnz     find_file

    ;------------------------------------
read_FAT_chunk:
    mov     eax, ebx
    shr     eax, 7			; eax = index of desired 512b chunk inside FAT

    ; check if desired 512 byte chunk is cached already
;    cmp     eax, ebp
;    jz      @f
;    mov     ebp, eax
;
    push    dword [si+4]
    add     eax, [si-offs-12]		; 512b index += beginning of FAT in 512b units
    mov     dword [si+4], $800		; read FAT chunk to 0:$800
    mov     dword [si+8], eax		; update low 32bit of LBA
    xor     cx, cx			; cl = 0, meaning one 512b chunk to read
    call    readDisk
    pop     dword [si+4]
;
;@@:
    and     bx, 127
    shl     bx, 2
    mov     ebx, [$800+bx]		; read next cluster index
    cmp     ebx, $0fff'fff0		; check if we reached end of cluster chain
.patch1:
    jb	    near fileSearch
@@:
    cmp     byte [.patch1+2], (copyClusters-read_FAT_chunk.patch1-4) and $ff
    jnz     Error

    jmp     $0:$8000


;===================================================================================================

fileNotFound: db "KIWI.IMG missing"

Error:
    mov     ax, 3
   ; int     $10
.1:
    cld
    mov     si, fileNotFound
    push    $b800
    pop     es
    xor     di, di
    mov     ah, $a
@@:
    lodsb
    cmp     al, $b8   ; this byte is part of 'mov ax,3' instruction
    jz	    .1
    stosw
    jmp     @b

;===================================================================================================

    ; temp	= lba / max_sectors_per_track
    ; sector	= (lba % max_sectors_per_track) + 1
    ; head	= temp % max_number_of_heads
    ; cylinder	= temp / max_number_of_head

    ; "int13 ah=2" code bellow doesn't validate max cylinder supported by disk/bios
    ; There are no retry attepmts if read fails.
    ; max head at [si-offs-4]
    ; max sector at [si-offs-8]

readDisk:
    push    ebx
    mov     byte [si+32], 1
    shl     byte [si+32], cl
.read:
    sti


    cmp     byte [si], $10
    jz	    .read_42h

    ;------------------------------------
.readLegacy:
    jmp     Error

;    mov     eax, [si+8]		; read lba addr
;    xor     edx, edx
;    div     dword [si-offs-8]		; divide by max spt(sectors per track)
;    inc     dx
;    mov     cl, dl			; cl = sectors
;
;    xor     edx, edx
;    div     dword [si-offs-4]		; divide by max heads
;
;    shl     ah, 6
;    mov     ch, al
;    or      cl, ah
;
;    mov     ax, fs
;    xchg    dl, dh			; dh = head
;    mov     dl, al			; dl = drive number
;
;    push    word [si+6]		; segment
;    mov     bx, [si+4] 		; offset
;    mov     ax, $201			; read one sector
;    pop     es
;    int     $13
;    jc      short Error
;    jmp     .advanceSector
;
    ;------------------------------------
.read_42h:

    mov     dx, fs
    mov     ah, $42
    int     $13
    jc	    short Error

    ;------------------------------------
.advanceSector:
    inc     dword [si+8]		; source address ++
    add     word [si+4], 512		; destination offset += sector size
    jnz     @f
    add     word [si+6], $1000		; destination segment++ if offset=0
@@:
    dec     byte [si+32]
    jnz     .read

    pop     ebx
    ret





;macro dsf{
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

.cursor dw 160
;}



    db (512-($-VBR)-2) dup('+')
    dw $aa55





























