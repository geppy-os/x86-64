
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


define IA32_STAR	0xc0000081
define IA32_LSTAR	0xc0000082
define IA32_FMASK	0xc0000084
define LAPIC_ID 	0x0020
define LAPIC_VER	0x0030
define LAPIC_APR	0x0090
define LAPIC_PPR	0x00a0
define LAPIC_EOI	0x00b0
define LAPIC_RRD	0x00c0
define LAPIC_LDR	0x00d0
define LAPIC_DFR	0x00e0
define LAPIC_SVR	0x00f0
define LAPICT		0x0320
define LAPICT_INIT	0x0380
define LAPICT_CURRENT	0x0390
define LAPICT_DIV	0x03e0
define LAPIC_MSR	0x1b		; IA32_APIC_BASE
define PG_PRESENT	1
define PG_P		1
define PG_RW		2
define PG_USER		4
define PG_PS		(1 shl 7)
define PG_G		(1 shl 8)
define PG_IO_ALLOC	(1 shl 9)	; page allocated for Memory Mapped IO
define PG_MORE_STACK	(1 shl 10)	; alloc more stack, upper page must be mapped and have this flag
define PG_ALLOC 	(1 shl 11)	; physical RAM will be supplied when accessed
define PG_ZERO_ONACCESS (1 shl ?)
define PG_ALLOC_USER	(1 shl ?)	; ?
define PG_XD		(1 shl 63)

; memory caching related
define IA32_PAT 	0x277
define PG_PWT		(1 shl 3)
define PG_PCD		(1 shl 4)
define PG_PAT		(1 shl 7)
define PG_MEM_UC
define PG_MEM_WB


struct RECT
  left		dd ?
  top		dd ?
  right 	dd ?
  bottom	dd ?
ends

struct RECTw
  left		dw ?
  top		dw ?
  right 	dw ?
  bottom	dw ?
ends

struct PCI
  addr		dd ?
  devVend	dd ?
  classcode	dd ?
  offset12	dd ?
  barIndex	dw ?
  barMask	dw ?
ends

struct VBE
  width 	dw ?
  height	dw ?
  lfb		dd ?
  bps		dw ?		; bytes per scanline
  bpp		db ?		; bits per pixel
  clrMode	db ?
  modeNumber	dw ?
  dummy 	db ?
  bytesPerPx	db ?
ends

struct DRAWBUFF
  ptr		dq ?
  width 	dd ?
  height	dd ?
  bpl		dd ?		; bytes per line
  bpp		dd ?		; bytes per pixel
  clip		RECT
ends

;--------------------------------------------------------------------------------------------------
; 800 threads per 16KB
; index in CPU private array = local to the CPU process id

struct THREAD
  next		dw ?		; next
  prev		dw ?		; prev (for priority lists)

  gTID		dw ?		; global Thread ID, if	=0 then we use predefined value for all
				;		    if !=0 then start with "physAddr" and "gTID"
				; gTID gives us linear addr and while we are inside timer
				; interrupt (ring0) - we can access everything at that linear addr

  time2run	dw ?		; time meant to run in microseconds, max 65.535 milliseconds
				;  TODO: need to check if (word * ticks-per-ms) fits into 0x6fffffff

  timeDidRun	dd ?		; time it ran last time (could be affected by timers)
				;    TODO: need better/longer period

;  timeLeft2run  dd ?		 ; positive - can still run, negative - ran too much
				 ;   Can accumulate over time.
				 ;   Affected by timers, interrupts, other thread switches.
ends


; if TIMER entry is not allocated then data2 = 2byte index of next free(unallocated) entry

struct TIMER
  returnPtr	dq ?
  data1 	dq ?
  data2 	dq ?
  wakeUpAt	dq ?		; low 4bytes time in milliseconds, top 4bytes = # of microseconds
  next		dw ?
  prev		dw ?
  gTID		dw ?		; global thread id
  cpuID 	dw ?
ends


struct TIMERS
  ptr		dq ?
  blockSz	dd ?
  1stFree	dd ?
  head		dd ?
  cnt		dd ?
  head2 	dd ?
  cnt2		dd ?
ends

