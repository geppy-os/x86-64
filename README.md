# Description

It's an x86-64 OS in its very early stages.
There is LAPIC, IOAPIC stuff, but not ACPI AML for PCI devices.
There is no dynamic mem alloc (malloc) but static(predefined addresses) is just fine.
Page Fault handler supplies RAM as needed (when 16KB chunk accessed).
An IDT entry can share many devices.
There is some graphics but no GUI just yet.
There are no devices supported except RTC and PS2 mouse & kbd.
There are timers with microsecond prcesion.
Thread structure is yet to be clearly defined.
Multi CPUs are coming up eventually.

# Installation

 Compile "geppy.asm" with FASM (found at http://flatassembler.net/download.php).
 FASM is available for Windows and Linux.

You need a ready to use bootable disk/usb/floppy/whatever that can run image resulted after compiling 'geppy.asm'. There are tons of options here so instructions are skipped.

# License

Well, It's GPL v1.
Will change if anyone interested in active help.
