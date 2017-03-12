
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



; This is the file that gets compiled to produce binary
;
;	     bios_boot.asm     executed first
; then	     kernel32.asm
; then	     kernel64.asm
; that's all

; most variables(memory locations) are defined in this file
; most constants and structs are in "const.inc"



	format binary as 'img'
	org 0x8000
	use16


	include 'struct-1.71.39.inc'

	; file "struct-1.71.39.inc" comes from Fasm package
	; and will not compile with earlier version of Fasm
	; min for "struct-1.71.39.inc" is Fasm v1.71

	; file "struct-1.70.02.inc" is for those who want to compile on Apple OS X
	; Fasm v1.70.02 compiler(assembler) for Mac can be found on fasm forum


	include 'const.inc'

macro reg1 {}

macro reg val{
	pushd	val
	call	reg16
}

	include 'bios_boot.asm'

macro reg val, flags{
	pushf
	push	eax
	mov	eax, dword val
	pushd	flags#h eax
	call	reg321
	pop	eax
	popf
}

	include 'kernel32.asm'

macro reg val, flags{
	pushfq
	push	rax
	mov	rax, qword val
	pushq	flags#h rax
	call	reg64
	pop	rax
	popfq
}
macro reg2 val, flags1{
	pushfq
	push	r8 r9
	mov	r8, val
	mov	r9, flags1
	call	reg64_
	pop	r9 r8
	popfq
}
macro ascii val, flags{
	pushf
	push	eax
	mov	eax, val
	pushd	flags#h eax
	call	ascii64
	pop	eax
	popf
}

	align 16
_pmode_ends:

	; executions continues to file kernel64.asm (included later, here in this file)


;===================================================================================================
;			 shared data, expected to be bellow 2nd MB
;===================================================================================================

; identity mapped (acpiLapicIDs & bootCpuInfotwo used once and forgotten)

acpiLapicIDs	= 0x7e000	; 1KB = 256 CPUs * 4 bytes;  index = 4byte acpiID; value = lapicID
bootCpuInfo	= 0x7f000	; 4KB = 256 CPUs * 16 bytes; index = lapicID

; not identity mapped

acpiTbl 	= 0x80000	; at 512KB linear
txtVidMem	= 0x1e2000	; 8KB
fragMem 	= 0x1e4000	; 32KB
ioapic		= 0x1f0000	; 4 times 4KB
hpet		= 0x1f4000	; 4 times 4KB
lapic		= 0x1f8000	; 4KB
data1		= 0x1fc000
threads 	= 0x1fd000	; 2KB (TODO: free up 4KB which belongs to "inst_devs" or "data3")
;data2		 = 0x1fd000
data3		= 0x1fe000
locks		= 0x1ff000

; vidDblBuff, vbeLfb, pcie are expected to be inside same Gigabyte
vidDblBuff	= 0x28000000	; (to be implemented)
vbeLfb		= 0x2c000000	; at 704MB, 64MB in size (must be 2MB aligned bellow 512GB)
pcie		= 0x30000000	; at 768MB, 256MB in size

gdt		= data1
gdtr		= data1 + 64
time		= data1 + 80
largestLapicID	= data1 + 96
time		= data1 + 112	; in 500ms units

kCpuId2lapic	= data1 + 1024	; Map kernel CPU id to LapicID; Array index = kCpuId
				; 4bytes entries(contains LapicID) * 256 CPUs = 1KB

isaDevs 	= data1 + 2048	; 16 20byte entries



ioapic_gin	= data1 + 2368	; 4bytes vars; array index = ioapic index; value = ACPI GlobIntNumber
				;				  if value = -1, ioapic doesn't exist
ioapic_inputCnt = data1 + 2384	; 4bytes = 1byte (for each ioapic) * 4
				; if 0 - corresponding ioapic doesn't exist (after 'parse_MADT runs')

calcTimerSpeed	= data1 + 2388	; runs on one cpu at a time
pciDevs_info1	= data1 + 2408	; 8b pointer to additional info for pci devices

k64_flags	= data1 + 2416	; bit0	=1 if we can use draw (some video was set sucessfully)
				; bit1	=1 if PS2 present
				; bit2	=1 if RTC present

screen		= data1 + 2424	; should be a 40byte struct here (VBE LFB)
vidBuff 	= data1 + 2504	; another 40byte (double buffer for vbe lfb)
vidBuff_changes = data1 + 2584	; RECT, region that was changed







	       ; bitmask made of kernlIDs(its index) to tell which device needs installation


ioapInfo	= data1 + 4040

drvOnDisk	= data1 + 4048
drvOnDisk_cnt	= data1 + 4056
drvOnDisk_sz	= 32		; size of one array entry in bytes

; +0  8byte device+vendor or classcode or smth else
; +8  2byte thread id
; +10 defines structure of 8 bytes at +0
; +11 ?
; +12 4byte offset within the thread
; +16 ?
; +30 next index of a 32byte driver enrtry


devInfo_ioapMax = data1 + 4060
ioapInfo_len	= data1 + 4064
ioapInfo_sz	= 12		; min 12bytes entry, max 32

;  initially empty array (when installing device - we add entries here)
; Does anything connected to certain ioapic input or not:
;-------------------------------------------------------
; 12byte entry:
;  array:  byte0: same format as in 32byte dev entry at +10 offset (with bits 2,3,4,5 masked)
;								      bit2 = has handler installed that
;									  doesn't support shared ints
;	   byte1: IOAPIC_input	     (same format as in 32byte dev entry at +11)
;	   dword: single DEV_ID or 0 (same format as in 32byte dev entry at +0 offset)
;	   word:  index to 32byte rss entry (to hold additional DEV_IDs)


;-------------------------------------------------------
;  we can have many entries with same ioapic info but different DEV_ID and need to browse thru them all
;  (TODO: maybe use 2byte index to connect several DEV_ID to same ioapic info ?)
;  (if we use 32byte entry then we'll have enough room for several DEV_IDs     )

devInfo_cnt2	= data1 + 4068	; ? counter of predefined entries (16 ISA + 4 PCI)
devInfo_1stFree = data1 + 4072	; 1st free entry that we can allocate or -1 if none
devInfo_cnt	= data1 + 4076	; counter of used entries
devInfo 	= data1 + 4080	; (devInfo + devInfo_ioapicSz) = 8byte ptr to the following entries:
devInfo_sz	= 32
;------------------------------------------------------
; 32 byte device entry (for PCI & ISA/ACPI/PNP devices)
;------------------------------------------------------
; +0   4byte kernel id(top 16bits = random #; bit15 =1 if PCI,	=0 if not PCI; lowest 15bits = index)
;									      if index=0 then invalid
; +4   4byte how its connected (A/B/C/D + bus/dev/func; or ACPI GIN)
;      if bit31 for PCI is set then regular IO, if cleared MMIO
;
; +8   flags	[0]   =1 if driver has no way to tell if interrupt was meant for this device or not
;
; +9   flags	[3:0] source bus irq for ISA; A/B/C/D for PCI
;		[4]   =1 if entry has some id at +16
;		[5]   =1 if entry has classcode at +24
;		[6]   =1 if driver not found on disk
;		[7]   =1 if driver assigned
;------------------------
; bytes 10,11 & 12,13: how can we connect this bus input/pin (later - device) to IOAPIC
;------------------------
; +10  1byte:
;	  ioapic kernel id	 [1:0]
;	  in-use		 [2]	=1 if bytes 10,11 were used to set up interrupt
;	  ?			 [3:4]
;	  valid ioapic info	 [5]	=1 if ioapic info is valid
;	  polarity		 [6]	high=0	low=1
;	  trigger		 [7]	edge=0, lvl=1
; +11  ioapic input 1byte
;------------------------
; +12  1byte:
;	  ioapic kernel id	 [1:0]
;	  in-use		 [2]	=1 if bytes 12,13 were used to set up interrupt
;	  ?			 [3:4]
;	  valid ioapic info	 [5]	=1 if ioapic info is valid
;	  polarity		 [6]	high=0	low=1
;	  trigger		 [7]	edge=0, lvl=1
; +13  ioapic input 1byte
;------------------------
; +14  2byte = thread id  (-1 is invalid = no thread assigned), assigned inside "dev_install"
; +16  8byte pci/acpi id: vendor(low dword) + device(top dword)
; +24  class code (3bytes)
; +27  ?
; +28  2byte index inside array that lists available device drivers (on disk or compiled with kernel)
; +30  2byte index for additional info
;
; +?  4byte = main interrupt handler (offset relative to the beginning of the thread space)
; +?  4byte = init function (offset relative to ... )
; +?  4byte = suspend device function (offset relative to ... )
; +?  0; or MSI index = index in IDT minus one (one handler per max 255 IDT entries))
;
;----------------------------------------------
; First, we check which devices installed on motherboard and build a table made of entries above.
; Second, we check which drives we have on disk and assign them to corresponding devices.
;   We also browse drivers that are compiled with the kernel in one binary and add them.
;   If we found required file(driver) on disk - we load the file, parse it and start the driver.
;	 need to cache file names, could be done by disk driver
;	 we could tell disk driver to cache one folder
;----------------------------------------------
; First 16 entries always considered taken and never freed. They ALSO represent 16 ISA bus inputs/pins.
; If more than 1 device on ISA input then we add more entries.
;----------------------------------------------
;????
; either user or dev driver or some table in memory needs to tell if anything connected to an ISA input
; if connected we look in first 16 entries device pol+trig+other_info and create new ISA entry
; not within first 16 entries ( source bus irq is irrelevent in this case )
; we can also reserve 4entries for PCI A/B/C/D to know how they connected
; first we parsed 16 ISA inputs then we parse 4 PCI ABCD and then we use all of that to add dev entries
;---------------------------------------------

kernelEnd_addr	= data1 + 4088	; address were we can copy more ring0 code, grows over time
inst_devs_cnt	= data1 + 4092
inst_devs	= data3 	; installed devices, one entry: +0 4byte id, +4 8byte address


;---------------------------------------------------------------------------------------------------
; don't change order of variables in the "lock" sections bellow
;---------------------------------------------------------------------------------------------------

memPtr		= locks + 128
memTotal	= locks + 136
memLock 	= locks + 140

gTimers 	= locks + 256

gThreadIDs	= locks + 512	; 64bytes = 512bits
gThreadIDs_lock = locks + 576


;

;===================================================================================================
;			 per CPU private data
;===================================================================================================

idt		equ	r15

;---------------------------------------------------------------------------------------------------

lapicT_stack	equ	r15+(4096+512)

lapicT_redraw	equ	r15+((4096+512)-144)	; 1b
lapicT_sysTID	equ	r15+((4096+512)-146)	; 2b, system thread id = always ring0 thread
lapicT_overhead equ	r15+((4096+512)-150)	; 4b, time it takes to execute the handler
lapicT_currTID	equ	r15+((4096+512)-152)	; ID of the thread that is running right now
						; changed inside lapicT handler or after noThreadSw
;lapicT_kPML4	 equ	 r15+((4096+512)-160)

lapicT_time	equ	r15+((4096+512)-168)	; 8b, Timer timeout.  Measured in lapic timer ticks.
						;  overflows only once if we add two 4byte values to it
						;___________________________________________________
lapicT_flags	equ	r15+((4096+512)-172)	; bit 0  =1 if no timer entry present on current list
						;___________________________________________________
						; bit 1  "lapicT_time" ID. Changes when "lapicT_time"
						;	  overflows. Beeing used to add timer entries
						;		      = "add_list" id for timers
						;___________________________________________________
						; bit 2  =1 if no thread switch requested
						;	    (used by noThreadSw, resumeThreadSw,
						;	     timer_in, thread_sleep)
						;___________________________________________________
						; bit 3  =1 if lapicT entered handler with bit2 set
						;	    (used by noThreadSw, resumeThreadSw,
						;	     timer_in, thread_sleep)
						;___________________________________________________

lapicT_pri3	equ	r15+((4096+512)-174)	; "head" index of the threads ready to run
lapicT_pri2	equ	r15+((4096+512)-176)
lapicT_pri1	equ	r15+((4096+512)-178)
lapicT_pri0	equ	r15+((4096+512)-180)
lapicT_priQuene equ	r15+((4096+512)-184)
rtc_cpuID	equ	r15+((4096+512)-185)	; 1b, RTC attached to this CPU id
rtc_job 	equ	r15+((4096+512)-186)	; 1b
lapicT_r15	equ	r15+((4096+512)-192)	; 6bytes, value of R15 in 64KB units


; var access from within the interrupt handler without using r15 register
;sp_lapicT_overhead equ     rsp+46
sp_lapicT_overhead equ	   rsp+42
sp_lapicT_currTID  equ	   rsp+40
;sp_lapicT_kPML4    equ     rsp+32
sp_lapicT_time	   equ	   rsp+24
sp_lapicT_flags    equ	   rsp+20
sp_lapicT_pri3	   equ	   rsp+18
sp_lapicT_pri2	   equ	   rsp+16
sp_lapicT_pri1	   equ	   rsp+14
sp_lapicT_pri0	   equ	   rsp+12
sp_lapicT_priQuene equ	   rsp+8
sp_rtc_cpuID	   equ	   rsp+7
sp_rtc_job	   equ	   rsp+6
sp_lapicT_r15	   equ	   rsp

;---------------------------------------------------------------------------------------------------
PF_stack	equ	r15+(4096+1024)

PF_?_2		equ	r15+((4096+1024)-122)	; 1byte
PF_pages	equ	r15+((4096+1024)-120)	; 1byte, holds max 127.5 MB
PF_2nd		equ	r15+((4096+1024)-121)	; 1byte
PF_?		equ	r15+((4096+1024)-122)	; 1byte
PF_r15		equ	r15+((4096+1024)-128)	; 6bytes, value of R15 in 64KB units

sp_PF_?_2	equ	rsp+16
sp_PF_pages	equ	rsp+8
sp_PF_2nd	equ	rsp+7
sp_PF_? 	equ	rsp+6
sp_PF_r15	equ	rsp

; PF_pages:
;---------------
; +0 bitmask 1byte, bit cleared - corresponding 4kb page mapped  (PF handler can only set bits)
; +1 last 4kb page that was used
; +2 cached size of the selected at +1 page
; +4 =0 if 4kb page with non-zeroed chunks, !=0 if 4kb with zeroed chunks
; +5 TODO: =1 if all pages (for which bit is set in "+0 bitmak") are unmapped
; +6 total mem mapped into PF_ram

;----------------------------------------
; the 4KB page that has 16KB RAM indexes
;----------------------------------------
; +0 size = number of 16kb indexes
; +4 =0 if 4kb page with non-zeroed chunks, !=0 if 4kb with zeroed chunks
; +8 8ytes undefined
;    pointer to next 16kb when pages are not mapped at PF_ram address (list terminated with 0 ptr)

;---------------------------------------------------------------------------------------------------

GP_stack	equ	r15+(4096+1536)

DF_stack	equ	r15+(4096+2048)

HPET1_stack	equ	r15+(4096+2560)

interrupt_stack equ	r15+(4096+3584) 	; 1 KB, enough?

;---------------------------------------------------------------------------------------------------

paging_ram	equ	r15+(8*1024)		; 4KB, RAM for PML4s, PDPs, PD tables (hosts 16KB chunks)

idtr		equ	r15+(12*1024)		; umm, never really used
pgRam4_size	equ	r15+(12*1024+12)
lapicT_ms	equ	r15+(12*1024+16)	; 4b, # of lapic timer ticks per millisecond
lapicT_ms_fract equ	r15+(12*1024+20)	; 4b,			       for the divider of 2
lapicT_us	equ	r15+(12*1024+24)	; 4b, each microsecond
lapicT_us_fract equ	r15+(12*1024+28)	; 4b
irqMask 	equ	r15+(12*1024+36)	; 12b, 192 IDT vectors (from 48 to 239)
kernelPanic	equ	r15+(12*1024+56)	; 4b
sysTasks	equ	r15+(12*1024+60)	; 8b
_?		equ	r15+(12*1024+68)	; 4b

;process_ptr	 equ	 r15+(12*1024+40)
;process_cnt	 equ	 r15+(12*1024+48)
;process_lock	 equ	 r15+(12*1024+52)

timers_local	equ	r15+(12*1024+72)	;
_?		equ	r15+(12*1024+100)
timers_head	equ	r15+(12*1024+104)	; 2 2byte vars
timers_cnt	equ	r15+(12*1024+108)	; 2 2byte vars
k64_flags	equ	r15+(12*1024+112)	; bit0 =1 if lapicT is active (can't put CPU to sleep)
feature_XD	equ	r15+(12*1024+120)
tss_data	equ	r15+(12*1024+128)	; TSS is closer to threads, same 4KB (2176=2048+128)


errF		equ	r15+(12*1024+384)	; increment index at the beginning of the function, store func id, dec at the end
						; function call trace

ps2_mouseBytes	equ	r15+(12*1024+388)	; 8b for PS2 Mouse
ps2_packetCnt	equ	r15+(12*1024+396)	; 4b, PS2 Mouse
ps2_packetMax	equ	r15+(12*1024+400)	; 4b, PS2 Mouse
ps2_mouseState	equ	r15+(12*1024+404)
ps2_kbdState	equ	r15+(12*1024+408)
ps2_mouseFlags	equ	r15+(12*1024+412)

_x		equ	r15+(12*1024+416)
_y		equ	r15+(12*1024+418)
_z		equ	r15+(12*1024+420)
_btns		equ	r15+(12*1024+422)
_xPrev		equ	r15+(12*1024+424)
_yPrev		equ	r15+(12*1024+426)
_x2		equ	r15+(12*1024+428)
_y2		equ	r15+(12*1024+430)


tscGranul	equ	r15+(12*1024+432)	; 16bytes total
lapicID 	equ	r15+(12*1024+448)	; 1b
lock1		equ	r15+(12*1024+449)	; 2b
?		equ	r15+(12*1024+451)
redrawFrame	equ	r15+(12*1024+456)	; 8b, in lapicT_time units
redrawTime	equ	r15+(12*1024+464)	; 8b



;threads	 equ	 r15+(13*1024)		 ; 3KB, its an array, thread id = index of thread entry

;pgRam4 	 equ	 r15+(16*1024)		 ; ? hmmm (hosts 4KB chunks?)

kStack		equ	r15+(28*1024)		; 8KB grows down, ( 4KB at 20*1024, 4KB at 24*1024 )

;			r15+(28*1024)		; intentionaly empty 4KB


PF_ram		equ	r15+(32*1024)		; 32KB
_?		equ	r15+(64*1024)		; 4KB left blank intentionally
clonePML4	equ	r15+(68*1024)		; for temporary pml4 mapping when creating a thread
_?		equ	r15+(72*1024)		; 4KB left blank intentionally

shared_IRQs	equ	r15+((76*1024)+0)	; ??? 768bytes = 192 vectors * 4byte addr bellow 4GB
_?		equ	r15+((76*1024)+768)

;=========================================================================  thread control block ===
; following offsets are relative to "user_data_rw"
;---------------------------------------------------------------------------------------------------
event_mask	=	0			; 8byte
functions	=	16

;==========================================================================  kernel only data  =====



;===================================================================================================

	include 'kernel64.asm'

	include 'threads.asm'
	include 'acpi_apic.asm'
	include 'int_handlers.asm'
	include 'rtc_cmos.asm'
	include 'lapic_timer.asm'
	include 'memory.asm'
	include 'ints_devs.asm'
	include 'pci.asm'
	include 'timers.asm'
	include 'files.asm'
	include 'bigDump/numbers.asm'
	include 'k64errors.asm'
	include 'crypt.asm'
	include "syscall.asm"

	include 'graph2d/graph2d.asm'		; 2D graphics, contains many "include"s
	include 'gui.asm'
	include 'mouse.asm'
	include 'debug/g2d_drawText.asm'

	; device drivers (best not to include printers, mouses or smth not vital)
basic_devDrivers:
	.cnt = 3

	dq	'PNP0100'
	db	0
	dd	@f-$-4
	file	'devices/thread2'
@@:
	dq	'PNP0100'
	db	0
	dd	@f-$-4
	file	'devices/thread1'
@@:
	dq	'PNP0120'			; PS2 Mouse & Kbd
	db	0
	dd	@f-$-4
	file	'devices/PNP0120'
@@:

	; filesystem drivers (most should have minimum read-only capabilities)
basic_fsDrivers:
	.cnt = 0


;===================================================================================================
;    read-only data for 64bit long mode
;===================================================================================================

LMode_data:

_idt_exceptions_lmode:
	dw	int_DE-int_handlers, int_DB-int_handlers, int_NMI-int_handlers
	dw	int_BP-int_handlers, int_OF-int_handlers, int_BR-int_handlers
	dw	int_UD-int_handlers, int_NM-int_handlers, int_DF-int_handlers
	dw	int_dummy2-int_handlers, int_TS-int_handlers, int_NP-int_handlers
	dw	int_SS-int_handlers, int_GP-int_handlers, int_PF-int_handlers
	dw	int_dummy1-int_handlers, int_MF-int_handlers, int_AC-int_handlers
	dw	int_MC-int_handlers, int_XM-int_handlers, int_VE-int_handlers
	dw	0
  .cnt = ($-_idt_exceptions_lmode)/2


sysCalls:
	dq setEntryPoint

;------------------------------------------------

kExports_libIDs:
    .0	dw 0		; length of the string bellow, if <=0 then this WORD is followed by 8byte addr
	dq LMode2	;				   when <0    (can use bit_15, btr)
;    .1:
;	 dw .2-$-2	 ; 15bit length(# of bytes) of the string bellow, can't be less than 8bytes
;	 db "C:\Drivers\acpi.lib"
;    .2:
;	 dw .3-$-2
;	 db "C:\Dr0-0-01"
;    .3:
;	 dw 0
;	 dq LMode2
    .4:
	dw -1		; terminated with any signed negative 2byte value

;------------------------------------------------ this table needs to be generated dynamically

kExports_func:
    dw 1			; number of library blocks

    ;---------------------------- block index = library id
    dw (@f-$-2)/4		; number of functions, can have a library with 0 functions

    dd reg64 - LMode		; offset in memory
    dd reg64 - LMode
    dd thread_sleep - LMode		; ptr ok
    dd reg64 - LMode
    dd timer_in - LMode 		; ptr ok
    dd timer_exit - LMode		; ptr ok
    dd syscall_k - LMode		; ptr ok
    dd reboot - LMode
    dd mouse_add_data - LMode
@@:
;    dw 0
;    dw 0
;
;    dw (@f-$-2)/4
;    dd reg64 - LMode
;    dd reg64 - LMode
;    dd reg64 - LMode
;@@:

;------------------------------------------------
	align 4
sys_calls:
    dd timer_in - LMode
    dd syscall_threadSleep - LMode
    dd syscall_intInstal - LMode
    dd reboot  - LMode


    .max = ($-4-sys_calls)/4

;------------------------------------------------
	align 8
text_directions:
       ;y   x
    db -1, -1		; up & left	0 000
    db -1, 0		; up		1 001
    db -1, 1		; up & right	2 010
    db 0, 1		; right 	3 011
    db 1, -1		; dn & left	4 100
    db 1, 0		; dn		5 101
    db 1, 1		; dn & right	6 110
    db 0, -1		; left		7 111


	include 'graph2d/fonts.inc'
	include 'graph2d/cursors.inc'
	include 'k64err_messages.inc'


vidDebug:	.x		dw 10	; +0 x
		.y		dw 200	; +2
		.len		dw 0	; +4
		.font		dw 0
		.clr		dd 0
				dw 0
		.ptr		dq 0	; +14
		.line		dw 0

_lmode_ends:


;===================================================================================================
; these vars are inititalized during 16bit or 32bit code, before we switch to LongMode
;---------------------------------------------------------------------------------------------------
; linear address = physical
;===================================================================================================

vbe_temp	= 0x1000	; 0:0x1000 address for ah=0x4f00

vars = 0			; accessed using GS segment (currently at 448KB = 0x7000_segment)
rmData = 448*1024

boot_disk	= vars + 0	; 1byte
max_pci_bus	= vars + 1	; 1b				       ; + rmData
txtVidCursor	= vars + 2	; 2b
acpi_mcfg	= vars + 4
acpi_dsdt	= vars + 8					       ; + rmData
acpi_facp	= vars + 12
acpi_rsdt	= vars + 16
acpi_apic	= vars + 20					       ; + rmData
acpi_facs	= vars + 24
acpi_hpet	= vars + 28
acpi_ssdt	= vars + 32	; 32 tables * 4bytes = 128b	       ; + rmData
acpi_ssdt_cnt	= vars + 160	; 16b
acpi_mcfg_len	= vars + 288
acpi_dsdt_len	= vars + 292					       ; + rmData
acpi_facp_len	= vars + 296
acpi_rsdt_len	= vars + 300
acpi_apic_len	= vars + 304
acpi_facs_len	= vars + 308					       ; + rmData
acpi_hpet_len	= vars + 312
acpi_ssdt_len	= vars + 316	; 16b
mp_table	= vars + 444					       ; + rmData
mp_table_len	= vars + 448

feature_PAT	= vars + 967	; 1byte, =1 if supported by BSP, Intel chapter 11.12.2 IA32_PAT MSR
				;     3bit index = PAT,PCD,PWT bits must be encoded in the page-table

;vid_doubleBuff  = vars + 968
vbeLfb_ptr	= vars + 976					       ; + rmData
pciDevs_cnt	= vars + 980	; 4bytes
memMap_cnt2	= vars + 986	; 4bytes
tscBits 	= vars + 990	; 16bytes, check individual bits in a byte and remember bits that never change

ebda_mem	= vars + 1008
vbeCap		= vars + 1012	; capabilities field
vbeMem		= vars + 1016					       ; + rmData
vidModes_sel	= vars + 1020	; selected video mode
vidModes_cnt	= vars + 1021	; total video modes		       ; + rmData
memMap_szFailed = vars + 1022
memMap_cnt	= vars + 1023					       ; + rmData

vars_end	= vars + 1024

memMap		= vars + 1024	; max 64 entries, 16bytes each, =1KB, all entries must be 16b aligned
vidModes	= vars + 2048	; max 128 entries, 16bytes each, =2KB
pciDevs 	= vars + 4096	; max 1024 entries, 16bytes each, =16KB
vbe_temp2	= vars + 20480
								       ; + rmData
dq 0x9198'7497'2048'2712
