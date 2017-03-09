
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	align 16

arrow_mask:
  dd	 0, 0xffffff, 0xffffff, 0xffffff, 0xffffff, 0xffffff, 0xffffff, 0xffffff
  dd	 0,	   0, 0xffffff, 0xffffff, 0xffffff, 0xffffff, 0xffffff, 0xffffff
  dd	 0,	   0,	     0, 0xffffff, 0xffffff, 0xffffff, 0xffffff, 0xffffff
  dd	 0,	   0,	     0,        0, 0xffffff, 0xffffff, 0xffffff, 0xffffff
  dd	 0,	   0,	     0,        0,	 0, 0xffffff, 0xffffff, 0xffffff
  dd	 0,	   0,	     0,        0,	 0,	   0, 0xffffff, 0xffffff
  dd	 0,	   0,	     0,        0,	 0,	   0,	     0, 0xffffff
  dd	 0,	   0,	     0,        0,	 0,	   0,	     0,        0

arrow_clr:
.cl1 = 0xff'00'00
.cl2 = 0x00'a0'80

  dd	.cl1,	 0,    0,    0,    0,	 0,    0,    0
  dd	.cl1, .cl1,    0,    0,    0,	 0,    0,    0
  dd	.cl1, .cl2, .cl1,    0,    0,	 0,    0,    0
  dd	.cl1, .cl2, .cl2, .cl1,    0,	 0,    0,    0
  dd	.cl1, .cl2, .cl2, .cl2, .cl1,	 0,    0,    0
  dd	.cl1, .cl2, .cl2, .cl2, .cl2, .cl1,    0,    0
  dd	.cl1, .cl2, .cl2, .cl2, .cl2, .cl2, .cl1,    0
  dd	.cl1, .cl2, .cl2, .cl1, .cl1, .cl2, .cl2, .cl1
