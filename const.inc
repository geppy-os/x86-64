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
define PG_RW		2
define PG_USER		4
define PG_PS		(1 shl 7)
define PG_G		(1 shl 8)
define PG_ALLOC_USER	(1 shl 10)
define PG_ALLOC 	(1 shl 11)
define PG_XD		(1 shl 63)


struct VBE

  width 	dw ?
  height	dw ?

  lfb		dd ?

  bps		dw ?	; bytes per scanline
  bpp		db ?	; bits per pixel
  clrMode	db ?

  modeNumber	dw ?
  dummy 	dw ?

ends

