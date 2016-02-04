
; Distributed under GPL v1 License
; All Rights Reserved.



; for dynamic allocations:
;   separate blocks for pnpName and pnpName.pnp (within 4GB)
;


; find ID(r9) and IRQ info in ACPI, load corresponding driver that provides int handler, save info
; in the data structure bellow


	align 4
pnpName:
	dd 3	; total number of 8byte entries

	;dd ...   # of entries at the following pointer
	;dq ...   pointer to dynamically allocated mem to continue the array


	; entries fixed size
	db "RSP",0
	dd .pnp1 - pnpName

	db "RNP",0
	dd .pnp2 - pnpName

	db "PNP",0
	dd .pnp - pnpName  ; this offset can be reduced to 30bits easily
			   ; remaining 2 bits could be used to indicate PCI device

	; we can put PCI vendor (from pci config space) here as it's not ASCII and won't conflict


.sz=16 ; =length of entry under "pnp" label and any other labels bellow that may appear in the future


; memory for the device ids can be preallocated after parsing ACPI
	align 4
.pnp:
	dd 3
	dd 'C400', init_ps2Mouse-LMode, 0,0
	dd 'C500', init_ps2Mouse-LMode, 0,0

	dd '0B00', rtc_init-LMode, rtc_int-LMode, 0 ; last dword can be qword which in turn a pointer
						  ; to MSI info
						  ; if byte #7 =1 one MSI addr
						  ; if byte #7 >1 ptr to multiple MSI addrs

	; pci dev is 4bytes hex for PCIe



;all ascii dev IDs have some bits (in ascii) that are never set
; or we can convert 4byte ascii into 2byte hex
; or we can extend 4byte dev ID to include PCI-dev-vend and PCI-classcode identification bit


;	 dd '0B00'  ; kernel ioapic id & input (maybe MSI info), PNP ID
;	 dd rtc_init-LMode, rtc_int-LMode, 0	 ; ? low 16bit - requested job by OS
						; ? top 16bit - job that was completed by device


.pnp1:
.pnp2:
	dd 0