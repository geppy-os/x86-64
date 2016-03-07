
; Distributed under GPL v1 License  ( www.gnu.org/licenses/old-licenses/gpl-1.0.html )
; All Rights Reserved.


	align 8
file_load_startup:

	; we enumerate files
	; and call file_load for each

	ret

	align 8
file_load:

	; ask for file size
	; thread_create gets up linear & phys addrs along with thread id
	; this function copies file to specific location
	; thread_finalize sets correct paging flags

	ret

	align 8
library_load:

	ret