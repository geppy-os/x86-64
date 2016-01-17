define IA32_STAR	0xc0000081
define IA32_LSTAR	0xc0000082
define IA32_FMASK	0xc0000084

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

