
text1: db "0x3afe730d2"
text1Len = $-text1


; within low 127 value we'll put european
; within top 127 cyrilic & europeans

font_7px:
	dw	.largest		; largest numerical symbols supported
	dw	0			; max height, almost max height
	dd	.SYMBOLS -font_7px

	dd	32 dup 0
	dw	0x3041, .space - .SYMBOLS
	dw	0x0000, .! - .SYMBOLS
	dw	0x0000, .double - .SYMBOLS
	dw	0x0000, .number - .SYMBOLS
	dw	0x0000, .dollar - .SYMBOLS
	dw	0x0000, .percent - .SYMBOLS
	dw	0x0000, .and - .SYMBOLS
	dw	0x0000, .single - .SYMBOLS
	dw	0x0000, .open3 - .SYMBOLS
	dw	0x0000, .close3 - .SYMBOLS
	dw	0x0000, .star - .SYMBOLS
	dw	0x0000, .plus - .SYMBOLS
	dw	0x0000, .coma - .SYMBOLS
	dw	0x0000, .minus - .SYMBOLS
	dw	0x0000, .dot - .SYMBOLS
	dw	0x0000, .div - .SYMBOLS
	dw	0x1059, .0 - .SYMBOLS
	dw	0x1049, .1 - .SYMBOLS
	dw	0x1059, .2 - .SYMBOLS
	dw	0x1059, .3 - .SYMBOLS
	dw	0x1059, .4 - .SYMBOLS
	dw	0x1059, .5 - .SYMBOLS
	dw	0x1059, .6 - .SYMBOLS
	dw	0x1059, .7 - .SYMBOLS
	dw	0x1059, .8 - .SYMBOLS
	dw	0x1059, .9 - .SYMBOLS
	dw	0x0000, .semicol - .SYMBOLS
	dw	0x0000, .dot_coma - .SYMBOLS
	dw	0x0000, .less - .SYMBOLS
	dw	0x0000, .equal - .SYMBOLS
	dw	0x0000, .greater - .SYMBOLS
	dw	0x0000, .question - .SYMBOLS
	dw	0x0000, .email - .SYMBOLS
	dw	0x0000, .A - .SYMBOLS
	dw	0x0000, .B - .SYMBOLS
	dw	0x0000, .C - .SYMBOLS
	dw	0x0000, .D - .SYMBOLS
	dw	0x0000, .E - .SYMBOLS
	dw	0x0000, .F - .SYMBOLS
	dw	0x0000, .G - .SYMBOLS
	dw	0x0000, .H - .SYMBOLS
	dw	0x0000, .I - .SYMBOLS
	dw	0x0000, .J - .SYMBOLS
	dw	0x0000, .K - .SYMBOLS
	dw	0x0000, .L - .SYMBOLS
	dw	0x0000, .M - .SYMBOLS
	dw	0x0000, .N - .SYMBOLS
	dw	0x0000, .O - .SYMBOLS
	dw	0x0000, .P - .SYMBOLS
	dw	0x0000, .Q - .SYMBOLS
	dw	0x0000, .R - .SYMBOLS
	dw	0x0000, .S - .SYMBOLS
	dw	0x0000, .T - .SYMBOLS
	dw	0x0000, .U - .SYMBOLS
	dw	0x0000, .V - .SYMBOLS
	dw	0x009a, .W - .SYMBOLS
	dw	0x0000, .X - .SYMBOLS
	dw	0x0000, .Y - .SYMBOLS
	dw	0x0000, .Z - .SYMBOLS
	dw	0x0000, .open2 - .SYMBOLS
	dw	0x0000, .reverseDiv - .SYMBOLS
	dw	0x0000, .close2 - .SYMBOLS
	dw	0x0000, .^ - .SYMBOLS
	dw	0x9061, ._ - .SYMBOLS
	dw	0x0000, .topComa - .SYMBOLS
	dw	0x3077, .a - .SYMBOLS  ; 4=width, 6=height, 2=y coordinate, spacers for right & left sides
	dw	0x006a, .b - .SYMBOLS
	dw	0x3067, .c - .SYMBOLS
	dw	0x006a, .d - .SYMBOLS
	dw	0x3067, .e - .SYMBOLS
	dw	0x004a, .f - .SYMBOLS
	dw	0x306a, .g - .SYMBOLS
	dw	0x006a, .h - .SYMBOLS
	dw	0x1019, .i - .SYMBOLS
	dw	0x102b, .j - .SYMBOLS
	dw	0x006a, .k - .SYMBOLS
	dw	0x001a, .l - .SYMBOLS
	dw	0x3097, .m - .SYMBOLS
	dw	0x3067, .n - .SYMBOLS
	dw	0x3067, .o - .SYMBOLS
	dw	0x306a, .p - .SYMBOLS
	dw	0x306a, .q - .SYMBOLS
	dw	0x3047, .r - .SYMBOLS
	dw	0x3067, .s - .SYMBOLS  ; 6=width, 7=height,
	dw	0x004a, .t - .SYMBOLS
	dw	0x3067, .u - .SYMBOLS
	dw	0x3057, .v - .SYMBOLS
	dw	0x3097, .w - .SYMBOLS
	dw	0x3077, .x - .SYMBOLS
	dw	0x305a, .y - .SYMBOLS
	dw	0x3057, .z - .SYMBOLS
	dw	0x0000, .open1 - .SYMBOLS
	dw	0x0000, .veritcal - .SYMBOLS
	dw	0x0000, .close1 - .SYMBOLS
	dw	0x0000, .tilda - .SYMBOLS
.largest = ($-font_7px-8)/4

;----------------------------------------
.SYMBOLS:
;----------------------------------------

.space: 	db 0
.!:
.double:
.number:
.dollar:
.percent:
.and:
.single:
.open3:
.close3:
.star:
.plus:
.coma:
.minus:
.dot:
.div:
.0:		db 001'01110b,1'10001'10b,0001'1000b,01'10001'1b,10001'100b,01110b
.1:		db 1100'1000b,1001'1010b,1000'1000b,1000'1000b,1000b
.2:		db 001'01110b,0'10001'10b,1000'1000b,10'00100'0b,00001'000b,11111b
.3:		db 001'01110b,0'10000'10b,1100'1000b,00'10000'0b,10001'100b,01110b
.4:		db 001'00001b,1'10001'10b,1111'1000b,00'10000'1b,10000'100b,10000b
.5:		db 001'11111b,1'00001'00b,1111'0000b,00'10000'0b,10000'100b,01111b
.6:		db 010'01100b,1'00001'00b,0001'0111b,01'10001'1b,10001'100b,01110b
.7:		db 000'11111b,0'01000'10b,0100'0100b,10'00010'0b,00001'000b,00001b
.8:		db 001'01110b,1'10001'10b,1110'1000b,01'10001'0b,10001'100b,01110b
.9:		db 001'01110b,1'10001'10b,0001'1000b,00'11110'1b,01000'100b,00110b
.semicol:
.dot_coma:
.less:
.equal:
.greater:
.question:
.email:
.A:
.B:
.C:
.D:
.E:
.F:
.G:
.H:
.I:
.J:
		db 11'111'000b,1'100'111'1b,011'110'10b,10'011'011b,1'100'101'1b,111'111'11b,000b
.K:
.L:
.M:
.N:
.O:
.P:
.Q:
		db 11'111'000b,1'100'111'1b,011'110'10b,10'011'011b,1'100'101'1b,111'111'11b,000b
.R:
.S:
.T:
.U:
.V:
.W:		db 00000001b, 00000011b, 00000110b, 10010'100b, 0010'0100b, 010'01001b, 10'010101b, 0'0101010b, 00100010b, 01000100b, 1000100'0b, 00b
.X:
.Y:
.Z:
.open2:
.reverseDiv:
.close2:
.^:
._:		db -1
.topComa:
.a:		db 1'0011110b,00'010000b,110'01000b, 0001'0111b, 00001'010b, 011110'01b, 1b
.b:		db 01'000001b,0001'0000b,011101'00b,01'100011b,0001'1000b,100001'10b,01'100011b,0111
.c:		db 01'011110b,0001'1000b,000001'00b,01'000001b,1110'1000b,01b
.d:		db 00'100000b,0000'1000b,101110'10b,01'110001b,0001'1000b,100001'10b,10'110001b,1011b
.e:		db 01'011110b,0001'1000b,111111'10b,01'000001b,1110'1000b,01b
.f:		db 0010'1100b,1111'0010b,0010'0010b,0010'0010b,0010'0010b
.g:		db 10'101100b,0001'1100b,100001'10b,10'100001b,1100'1100b,100000'10b,10'100001b,0111b
.h:		db 01'000001b,0001'0000b,011101'00b,01'100011b,0001'1000b,100001'10b,01'100001b,1000b
.i:		db 11111101b,1b
.j:		db 10100010b,10101010b,011010b
.k:		db 01'000001b,0001'0000b,010001'00b,01'001001b,0111'0001b,001001'00b,01'010001b,1000b
.l:		db 11111111b,11b
.m:		db 11001101b,0110011'0b,010001'10b,10001'100b,0001'1000b,001'10001b,01'100010b,1000100b
.n:		db 11'011101b,0001'1000b,100001'10b,01'100001b,0001'1000b,10b
.o:		db 01'011110b,0001'1000b,100001'10b,01'100001b,1110'1000b,01b
.p:		db 11'011101b,0001'1000b,100001'10b,11'100001b,1101'1000b,000001'01b,01'000001b,0000
.q:		db 01'101110b,0001'1100b,100001'10b,01'100001b,1110'1100b,100000'10b,00'100000b,1000b
.r:		db 0011'1101b,0001'0001b,0001'0001b,0001b
.s:		db 01'011110b,0001'1000b,011110'00b,01'100000b,1110'1000b,01b
.t:		db 0010'0010b,1111'0010b,0010'0010b,0010'0010b,1100'0010b
.u:		db 01'100001b,0001'1000b,100001'10b,01'100001b,1110'1100b,10b
.v:		db 001'10001b,0'10001'10b,1010'0101b,00'01010'0b,001b
.w:		db 00000001b,0010001'1b,010010'10b,01010'010b,1010'0101b,100'01010b,00'001000b,0010001b
.x:		db 0'1000001b,00'010001b,000'00101b,0100'0001b,00010'001b,000001'01b,1
.y:		db 001'10001b,0'10001'10b,1010'0101b,00'01010'0b,00100'001b,011'00100b,00
.z:		db 000'11111b,0'01000'10b,0010'0010b,11'00001'0b,111b
.open1:
.veritcal:
.close1:
.tilda:

; must terminate with additional 0 byte or else we have 2byte pointer to another symbol ?
; or 1bit after with+height ends


