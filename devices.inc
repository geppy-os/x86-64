
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.





; info bellow is hardcoded at starup and updated as we browse files(drivers) on disk

; PCI/ACPI enumeration tells us which devices present on the computer and we look up info here

	align 4
dev_vendors:
	dd 16				; header size
	dd dev_vendOffs - dev_vendors
	dd .isa 			; total number of ISA/ACPI entries
	dd .pci 			; total number of PCI entries

@@:

	db "RSP",0
	db "ACPI"
	db "RNP",0
	db "PNP",0



.isa = ($-@b)/4
@@:

	dw 0x8086, 0			; vendor id followed by device id
	dw -1,-1			; invalid vendor followed by 3byte classcode


.pci = ($-@b)/4

dev_vendOffs:
	dd .pnp1 - dev_vendOffs
	dd .pnp1 - dev_vendOffs
	dd .pnp2 - dev_vendOffs
	dd .pnp - dev_vendOffs
	dd .intel - dev_vendOffs
	dd .pci_classcode - dev_vendOffs
.pnp:
	dd 3					; msi available, msi in use bits

	dd 'C400', init_ps2Mouse-LMode, 0	; 2bytes for ioapic input & kernel id

	dd 'C500'				; device id
	dd ps2_init-LMode			; offset to initialization function
	dd 0x1c'00'00'00			; top byte3: up to 2 default legacy interrupts (1 & c)
						;			 zero is not a valid interrupt
						; byte2:
						; byte1:
						; lowest byte0: device type (ISA,PCI)

	dd '0B00', rtc_init-LMode, 0x08'00'00'00

.pnp1:
.pnp2:
.intel:
.pci_classcode:
	dd 0					; device id
						; offset to initialization function
						; top byte3: legacy INT A/B/C/D
						; byte2:
						; byte1:
						; lowest byte0:


						; last dword can be MSI info
						; ? low 16bit - requested job by OS
						; ? top 16bit - job that was completed by device