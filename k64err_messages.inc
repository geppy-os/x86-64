
k64err_messages:

	dw .0-._
	dw .1-._
	dw .2-._
	dw .3-._
	dw .4-._
	dw .5-._
	dw .6-._
	dw .7-._
	dw .8-._
	dw .9-._
	dw .10-._
	dw .11-._
	dw .12-._
	dw .13-._
	dw .14-._
	dw .15-._
	dw .16-._
	dw .17-._
	dw .18-._
	dw .19-._
	dw .20-._
	dw .21-._
	dw .22-._
	dw .23-._
	dw .24-._
	dw .25-._
	dw .26-._
	dw .27-._
	dw .28-._
	dw .29-._
	dw .30-._
	dw .31-._
	dw .32-._
	dw .33-._
	dw .34-._
	dw .35-._
	dw .36-._
	dw .37-._
	dw .38-._
	dw .39-._
	dw .40-._
	dw .41-._
	dw .42-._
	dw .43-._
	dw .44-._
	dw .45-._
	dw .46-._
	dw .47-._

._:

.0  db "#pf: 2nd pf",0			; #PF happend while executing PF handler
.1  db "#pf: no pg_alloc",0		; PG_ALLOC is not set in PTe
.2  db "#pf: empty pf_pages bitmask",0	; empty = all 8 bits are set
.3  db "#pf: invalid pml4e",0
.4  db "#pf: invalid pdpe",0
.5  db "#pf: invalid pde",0
.6  db "#pf: addr top bits are 1s",0
.7  db "#pf:",0
.8  db "unknown kernel panic",0
.9  db "#gp:",0
.10 db "#df:",0
.11 db "#pf: p must be 0 in a pte",0
.12 db "size of shared int handler",0
.13 db "wrong count of shared ints on init",0
.14 db "shared int hndl - large addr",0
.15 db "unknown rtc",0
.16 db "lapT: no threads",0
.17 db "too many or liitle lapT ticks",0
.18 db "invalid syscall num",0
.19 db "syscall returned err",0
.20 db "thrd_sleep.sl already sleeping",0
.21 db "thrd_sleep.sl invalid prev next",0
.22 db "thrd_sleep_executeAfterINT20",0
.23 db "timer_in min 10us",0
.24 db "timer_in max 1sec",0
.25 db "lapicT: threads doesnt sleep",0
.26 db "dev_find: wrong input",0
.27 db "rtc: init1",0
.28 db "rtc: init2",0
.29 db "rtc: init3",0
.30 db "rtc: init4",0
.31 db "dev_find: wrong header",0
.32 db "no valid ioapics",0
.33 db "rtc: not present",0
.34 db "no enought isa devs",0
.35 db "int_install: small dev num",0
.36 db "int_install: large dev num",0
.37 db "int_install: supplied dev_id doesnt match",0
.38 db "int_install: no ioapic info",0
.39 db "int_install: dest ioap input outside mem",0
.40 db "int_install: handler present",0
.41 db "int_install: no free entry in idt",0
.42 db "madt",0
.43 db "fadt",0
.44 db "int_install: ioapic idt vector taken",0
.45 db "int_install: not masked",0
.46 db "int_install: non shared handler present",0
.47 db "max thread",0

k64err_messages_len = $-k64err_messages



