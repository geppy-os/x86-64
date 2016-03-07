
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



; This is main file that gets compiled.
;
;	     bios_boot.asm     executed first
; then	     kernel32.asm
; then	     kernel64.asm
; that's all

; most variables(memory locations) are defined in this file
; most constants and offsets are in "const.inc"



	format binary as 'img'
	org 0x8000
	use16


	include 'struct.inc'
	include 'const.inc'

macro reg val{
	pushd	  val
	call	  reg16
}

	include 'bios_boot.asm'

macro reg val, flags{
	pushf
	push	  eax
	mov	  eax, val
	pushd	  flags#h eax
	call	  reg32
	pop	  eax
	popf
}

	include 'kernel32.asm'

macro reg val, flags{
	pushfq
	push	  rax
	mov	  rax, val
	pushq	  flags#h rax
	call	  reg64
	pop	  rax
	popfq
}
macro ascii val, flags{
	pushf
	push	  eax
	mov	  eax, val
	pushd	  flags#h eax
	call	  ascii64
	pop	  eax
	popf
}

	align 16
_pmode_ends:

;===================================================================================================
;			 shared data
;===================================================================================================


; identity mapped (most used once and forgotten)

acpiLapicIDs	= 0x7e000	; 1KB = 256 CPUs * 4 bytes;  index = 4byte acpiID; value = lapicID
bootCpuInfo	= 0x7f000	; 4KB = 256 CPUs * 16 bytes; index = lapicID

; not identity mapped

acpiTbl = 0x80000	; at 512KB linear
fragMem = 0x1e4000	; 32KB
ioapic	= 0x1f0000	; 4 times 4KB
hpet	= 0x1f4000	; 4 times 4KB
lapic	= 0x1f8000	; 4KB
data1	= 0x1fc000
data2	= 0x1fd000
data3	= 0x1fe000
locks	= 0x1ff000
vbeLfb	= 0x2d000000	; at 720MB, 48MB in size
pcie	= 0x30000000	; at 768MB, 256MB in size

gdt		= data1
gdtr		= data1 + 64
time		= data1 + 80
largestLapicID	= data1 + 96
time		= data1 + 112	; in 500ms units

kCpuId2lapic	= data1 + 1024	; Map kernel CPU id to LapicID; Array index = kCpuId
				; 4bytes entries(contains LapicID) * 256 CPUs = 1KB
isaDevs 	= data1 + 2048
ioapic_gin	= data1 + 2368	; 4bytes vars; array index = ioapic index; value = ACPI GlobIntNumber
				;				  if value = -1, ioapic doesn't exist
ioapic_inputCnt = data1 + 2384	; 4bytes = 1byte (for each ioapic) * 4
				; if 0 - corresponding ioapic doesn't exist (after 'parse_MADT runs')

calcTimerSpeed	= data1 + 2388	; runs on one cpu at a time
_?		= data1 + 2408 ;2440

;---------------------------------------------------------------------------------------------------
; don't change order of variables in the "lock" sections bellow
;---------------------------------------------------------------------------------------------------

memPtr		= locks + 128
memTotal	= locks + 136
memLock 	= locks + 140

gTimers 	= locks + 256

gThreadIDs	= locks + 512	; 32bytes = 256bits
gThreadIDs_lock = locks + 544

; 20byte device entry (for PCI & ISA busses)
;-----------------------------------
; +0   ISA PNP	 or    8byte dev+vendor id    (temporarily = 4byte acpi GlobIntNumber)
;
; +8   3byte class code (pci)
;
; +11  ioapic input 1byte
;
; +12  1byte:
;	  iopaic id 4bits	 [3:0]
;	  trigger bit		 [4]
;	  polarity trigger	 [5]
;	  undefined bit 	 [6]
;	  bit=1 if entry valid	 [7]
;
; +13	3byte offset to additional info in 8byte units
;
; +16	4byte pci bus/dev/func
;

;===================================================================================================
;			 per CPU private data
;===================================================================================================

idt		equ	r15

;---------------------------------------------------------------------------------------------------

lapicT_stack	equ	r15+(4096+512)

lapicT_overhead equ	r15+((4096+512)-150)	; 4b, time it takes to execute the handler
lapicT_currTID	equ	r15+((4096+512)-152)	; ID of most recent thread that was or is running
						; Thread could be asleep with no other threads active
lapicT_kPML4	equ	r15+((4096+512)-160)

lapicT_time	equ	r15+((4096+512)-168)	; Single timer timeout must be a value that fits fully
						; into this variable (smaller than unsigned dword).
						; Microsecond units. ? LAPICT_INIT varies depending on CPU

lapicT_flags	equ	r15+((4096+512)-172)	; bit 0  remove_list id (set after we remove smth and
						;			there is still something left)
						; bit 1  "lapicT_time" ID. Changes when "lapicT_time"
						;	     overflows. Is used to add timer entries.
						; bit 2  =1 if no thread switch requested
						; bit 3  =1 if lapicT entered handler with bit2 set
						; bit 4  =1 if we did switch ID of the add_list

lapicT_pri3	equ	r15+((4096+512)-174)	; "head" index of the threads ready to run
lapicT_pri2	equ	r15+((4096+512)-176)
lapicT_pri1	equ	r15+((4096+512)-178)
lapicT_pri0	equ	r15+((4096+512)-180)
lapicT_priQuene equ	r15+((4096+512)-184)
rtc_cpuID	equ	r15+((4096+512)-185)	; 1b, RTC attached to this CPU id
rtc_job 	equ	r15+((4096+512)-186)	; 1b
lapicT_r15	equ	r15+((4096+512)-192)	; 6bytes, value of R15 in 64KB units

sp_lapicT_overhead equ	   rsp+42
sp_lapicT_currTID  equ	   rsp+40
sp_lapicT_kPML4    equ	   rsp+32
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

PF_?_2		equ	r15+((4096+1024)-122)	; 8bytes
PF_pages	equ	r15+((4096+1024)-120)	; 8bytes
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

interrupt_stack equ	r15+(4096+3072)

paging_ram	equ	r15+(8*1024)		; 4KB

idtr		equ	r15+(12*1024)		; umm, never really used
pgRam4_size	equ	r15+(12*1024+12)
lapicT_ms	equ	r15+(12*1024+16)	; 4b, # of lapic timer ticks per millisecond
lapicT_ms_fract equ	r15+(12*1024+20)	; 4b,			       for the divider of 2
lapicT_us	equ	r15+(12*1024+24)	; 4b, each microsecond
lapicT_us_fract equ	r15+(12*1024+28)	; 4b
process_ptr	equ	r15+(12*1024+40)
process_cnt	equ	r15+(12*1024+48)
process_lock	equ	r15+(12*1024+52)
_?		equ	r15+(12*1024+56)	; 4b
_?		equ	r15+(12*1024+60)
kernelPanic	equ	r15+(12*1024+64)	; 8b
timers1 	equ	r15+(12*1024+72)	;
timers_local	equ	r15+(12*1024+72)	;
_?		equ	r15+(12*1024+100)
timers_head	equ	r15+(12*1024+104)	; 2 2byte vars
timers_cnt	equ	r15+(12*1024+108)	; 2 2byte vars
k64_flags	equ	r15+(12*1024+112)	; bit0 =1 if lapicT is active (can't put CPU to sleep)
feature_XD	equ	r15+(12*1024+120)
tss_data	equ	r15+(12*1024+128)	; TSS is closer to threads, same 4KB (2176=2048+128)


errF		equ	r15+(12*1024+384)	; increment index at the beginning of the function, store func id, dec at the end
						; function call trace
_?		equ	r15+(12*1024+388)

threads 	equ	r15+(13*1024)		; 3KB, its an array, thread id = index of thread entry

pgRam4		equ	r15+(16*1024)

kStack		equ	r15+(28*1024)		; 8KB ( 4KB at 20*1024, 4KB at 24*1024 )

registers	equ	r15+(28*1024)		; 4KB

PF_ram		equ	r15+(32*1024)		; 32KB

;===================================================================================================

	include 'macros.inc'
	include 'kernel64.asm'

	include 'threads.asm'
	include 'acpi_apic.asm'
	include 'int_handlers.asm'
	include 'rtc_cmos.asm'
	include 'lapic_timer.asm'
	include 'memory.asm'
	include 'devices_ints.asm'
	include 'pci.asm'
	include 'timers_alerts.asm'
	include 'files.asm'

	include 'bigDump/numbers.asm'

	include 'thread1.asm'
	include 'thread2.asm'

;===================================================================================================
;    read-only data for 64bit long mode
;===================================================================================================

LMode_data:

	include 'errors.inc'
	include 'plug_and_play.inc'

_idt_exceptions_lmode:
	dw	int_DE-int_handlers, int_DB-int_handlers, int_NMI-int_handlers
	dw	int_BP-int_handlers, int_OF-int_handlers, int_BR-int_handlers
	dw	int_UD-int_handlers, int_NM-int_handlers, int_DF-int_handlers
	dw	int_dummy2-int_handlers, int_TS-int_handlers, int_NP-int_handlers
	dw	int_SS-int_handlers, int_GP-int_handlers, int_PF-int_handlers
	dw	int_dummy1-int_handlers, int_MF-int_handlers, int_AC-int_handlers
	dw	int_MC-int_handlers, int_XM-int_handlers, int_VE-int_handlers
  .cnt = ($-_idt_exceptions_lmode)/2

_lmode_ends:


;===================================================================================================
vbe_temp	= 0x1000	; 0:0x1000 address for ah=0x4f00

vars = 0			; accessed using GS segment (currently at 448KB = 0x7000_segment)
rmData = 448*1024

boot_disk	= vars + 0	; 1byte
max_pci_bus	= vars + 1	; 1b
___?		= vars + 2
acpi_mcfg	= vars + 4
acpi_dsdt	= vars + 8
acpi_facp	= vars + 12
acpi_rsdt	= vars + 16
acpi_apic	= vars + 20
acpi_facs	= vars + 24
acpi_hpet	= vars + 28
acpi_ssdt	= vars + 32	; 32 * 4bytes = 128b
acpi_ssdt_cnt	= vars + 160	; 16b
acpi_mcfg_len	= vars + 288
acpi_dsdt_len	= vars + 292
acpi_facp_len	= vars + 296
acpi_rsdt_len	= vars + 300
acpi_apic_len	= vars + 304
acpi_facs_len	= vars + 308
acpi_hpet_len	= vars + 312
acpi_ssdt_len	= vars + 316	; 16b
mp_table	= vars + 444
mp_table_len	= vars + 448

memMap_cnt2	= vars + 986	; 4bytes
tscBits 	= vars + 990	; 16bytes, check individual bits in a byte and remember bits that never change

ebda_mem	= vars + 1008
vbeCap		= vars + 1012	; capabilities field
vbeMem		= vars + 1016
vidModes_sel	= vars + 1020	; selected video mode
vidModes_cnt	= vars + 1021	; total video modes
memMap_szFailed = vars + 1022
memMap_cnt	= vars + 1023

vars_end	= vars + 1024

memMap		= vars + 1024	; max 64 entries, 16bytes each, =1KB, all entries must be 16b aligned
vidModes	= vars + 2048	; max 128 entries, 16bytes each, =2KB
vbe_temp2	= vars + 4096

dq 0x9198'7497'2048'2712
