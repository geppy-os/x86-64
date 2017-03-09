
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.



; for "k64_flags" variable

define FLAGS_PS2	(1 shl 1)
define FLAGS_RTC	(1 shl 2)

;0xfffffff0 is max value for LocalAPIC Timer, regadless how divider is set


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

define RTC_vector	0xf1		; entry index in IDT
define LAPICT_vector	0x20		; entry index in IDT

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
;define PG_ZERO_ONACCESS (1 shl ?)
;define PG_ALLOC_USER	 (1 shl ?)	 ; ?
define PG_XD		(1 shl 63)


define IA32_PAT 	0x277
define PG_PWT		(1 shl 3)
define PG_PCD		(1 shl 4)
define PG_PAT		(1 shl 7)	; conflicts with PG_S (2MB & 1GB pages)
					;	 Intel ch 11.12.4 (Programming the PAT)
define MAX_THREAD	255

					;   and have WC mem for VBE LFB that uses 4KB & 2MB pages
define IA32_MTRR_PHYSBASE	0x200
define IA32_MTRR_PHYSMASK0	0x201
define IA32_MTRR_PHYSBASE1	0x202
define IA32_MTRR_PHYSMASK1	0x203
define IA32_MTRR_PHYSBASE2	0x204
define IA32_MTRR_PHYSMASK2	0x205
define IA32_MTRR_PHYSBASE3	0x206
define IA32_MTRR_PHYSMASK3	0x207
define IA32_MTRR_PHYSBASE4	0x208
define IA32_MTRR_PHYSMASK4	0x209
define IA32_MTRR_PHYSBASE5	0x20A
define IA32_MTRR_PHYSMASK5	0x20B
define IA32_MTRR_PHYSBASE6	0x20C
define IA32_MTRR_PHYSMASK6	0x20D
define IA32_MTRR_PHYSBASE7	0x20E
define IA32_MTRR_PHYSMASK7	0x20F
define IA32_MTRR_PHYSBASE8	0x210
define IA32_MTRR_PHYSMASK8	0x211
define IA32_MTRR_PHYSBASE9	0x212
define IA32_MTRR_PHYSMASK9	0x213
define IA32_MTRR_FIX64K_	0x250
define IA32_MTRR_FIX16K_	0x258
define IA32_MTRR_FIX16K_	0x259
define IA32_MTRR_FIX4K_C0000	0x268
define IA32_MTRR_FIX4K_C8000	0x269
define IA32_MTRR_FIX4K_D0000	0x26A
define IA32_MTRR_FIX4K_D8000	0x26B
define IA32_MTRR_FIX4K_E0000	0x26C
define IA32_MTRR_FIX4K_E8000	0x26D
define IA32_MTRR_FIX4K_F0000	0x26E
define IA32_MTRR_FIX4K_F8000	0x26F
define IA32_MTRR_DEF_TYPE	0x2FF

define PG_MEM_UC
define PG_MEM_WB

define LIB_SYS			0
define FUNC_reg64		0
define FUNC0_dd2asciiDec	1
define FUNC0_thread_sleep	2
define FUNC0_u			3
define FUNC0_timer_in		4
define FUNC0_timer_exit 	5
define FUNC0_syscall		6

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

struct BOX
  x		dd ?
  y		dd ?
  width 	dd ?
  height	dd ?
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

; 40bytes
struct DRAWBUFF
  ptr		dq ?
  width 	dd ?
  height	dd ?
  bpl		dd ?		; bytes per line
  bpp		dd ?		; bytes per pixel
  clip		RECT
ends

;--------------------------------------------------------------------------------------------------
; All THREAD structures are located in shared among all CPUs memory.
; Pointers to the lists of THREADs are in CPU private memory to avoid needless locks.
; Each thread can belong to one CPU and can be managed by one CPU only.
; Each thread can only belong to one priority list.
;--------------------------------------------------------------------------------------------------
; A thread occupies max 512GB and starts at a multiple of 512GB addresses ( 0b, 512GB, 1GB, ...).
; All code in the thread is meant to be position independant.
; All threads are mapped at the same time into system pml4 table.
;     Thus, no two thread can share same 512GB space. Shared data access is allowed of course.
;--------------------------------------------------------------------------------------------------
; stack goes at the end of 512GB
; so it turns out that each thread gets its own entry in pml4 (with entirely private PDP)
; one thread is meant to be separate program/application
; any logic within the thread (aka task) is to be done by means of asynchronyous event processing
; we'll see how it turns out
;--------------------------------------------------------------------------------------------------
; thread id = gTID = THREAD struct index in shared memory
; each CPU has its own system thread
; system gTID is different for each CPU, but all sys threads run same code with diffrent data
;--------------------------------------------------------------------------------------------------
; One 512GB chunk is designated for non position independed code.
; Running addr of legacy application gets hardcoded during compilation of that app.
; Additional threadID info is used in this case.
;--------------------------------------------------------------------------------------------------
; in Geppy, "thread" is the the same as "process"
;--------------------------------------------------------------------------------------------------

; 20 bytes at the moment
struct THREAD
  next		dw ?		; next
  prev		dw ?		; prev (for priority lists)

  pml4		dd ?		; 6byte (mov rax, qword [THREAD.pml4-2]    shr rax,16)
		dw ?		;      must fill pml4 in the THREAD struct before ANY other variable

  time2run	dw ?		; time to run in microseconds, max 65535 milliseconds

  timeDidRun	dw ?		; TODO: time it ran last time (could be affected by timers as well)
		db ?

  flags 	db ?		; contains 1byte (max value of 3) priority list id, at the moment
  eventMask	dd ?
  return_RIP	dq ?

;  timeLeft2run  dd ?		 ; positive - can still run, negative - ran too much
				 ;   Can accumulate over time.
				 ;   Affected by timers, interrupts, other thread switches.
ends


;--------------------------------------------------------------------------------------------------
; From kernel viewpoint - max 1 timer (call of "timer_in" func) is allowed per thread =
;									     fixed kernel mem usage
; BUT we can make a list of user callback functions that are meant to fire at the same time
; If Thread is executing a timer handler then new timer is attached in local list and will be
; executed after current timer finishes.
;--------------------------------------------------------------------------------------------------
; if TIMER entry is not allocated then data2 = 2byte index of next free(unallocated) entry
;--------------------------------------------------------------------------------------------------
; Across multiple threads:
; Each timer handler is allowed to run for 4ms without interruption! (no other timers or events).
; If thread_1 sets a timer at 0x500 ms time and thread_2 at 0x501 ms (it is 1ms difference) then we
;    create some local queue in kernel (no TIMER enties at "timer_local" pointer)
; When thread_1 timer exits - we either fire thread_2 timer right away or add new TIMER entry
;--------------------------------------------------------------------------------------------------


struct TIMER
  handlerPtr	dq ?
  data1 	dq ?
  data2 	dq ?
  wakeUpAt	dq ?		; 8byte, same as "lapicT_time" units
  next		dw ?
  prev		dw ?
  gTID		dw ?		; global thread id
  cpuID 	dw ?
ends

; TIMERS struct holds a pointer to a block of TIMER entries
struct TIMERS
  ptr		dq ?
  blockSz	dd ?
  1stFree	dd ?
  head		dd ?
  cnt		dd ?
  head2 	dd ?
  cnt2		dd ?
ends

