
; Distributed under GPLv1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


define txtVidMem	0x1e2000
define txtVidCursor	(448*1024+2)
define lapic		0x1f8000
define LAPIC_EOI	0x00b0

define LIB_SYS			0

define FUNC0_reg64		0
define FUNC0_dd2asciiDec	1
define FUNC0_thread_sleep	2
define FUNC0_u			3
define FUNC0_timer_in		4
define FUNC0_timer_exit 	5
define FUNC0_syscall		6

define sys_timerIn		0
define sys_sleep		1
define sys_intInstall		2