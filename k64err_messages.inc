
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
._:

.0  db "#pf: 2nd pf",0		       ; #PF happend while executing PF handler
.1  db "#pf: no pg_alloc",0	       ; PG_ALLOC is not set in PTe
.2  db "#pf: empty pf_pages bitmask",0 ; empty = all 8 bits are set
.3  db "#pf: invalid pml4e",0
.4  db "#pf: invalid pdpe",0
.5  db "#pf: invalid pde",0
.6  db "#pf: addr top bits are 1s",0
.7  db "#pf:",0
.8  db "unknown kernel panic",0
.9  db "#gp:",0
.10 db "#df:",0
.11 db "#pf: p must be 0 in a pte",0

k64err_messages_len = $-k64err_messages



