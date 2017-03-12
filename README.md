# Description

It's an x86-64 OS in its very early stages.
There is LAPIC, IOAPIC stuff, but not ACPI AML for PCI devices.
There is no dynamic mem alloc (malloc) but static(predefined addresses) is just fine.
Page Fault handler supplies RAM as needed (when 16KB chunk accessed).
An IDT entry can share many devices.
There is some graphics but no GUI just yet.
There are no devices supported except RTC and PS2 mouse+kbd.
There are timers with microsecond prcesion.
Multi CPUs are coming up eventually.

# Installation

Compile "geppy.asm" with FASM (found at http://flatassembler.net/download.php).
FASM is available for Windows and Linux.

You need a ready to use bootable disk/usb/floppy/whatever that can run image resulted after compiling 'geppy.asm'. There are tons of options here so instructions are skipped.

# Installation on Linux

sudo fdisk -l

find your flash driver, i'll be using /dev/sde

sudo fdisk /dev/sde

your goal is to create primary partition on empty drive.
use following options inside fdisk: o - create dos partition table
				    n - create new partition, make it primary
				    a - set boot flag
				    t - set partition type, make it "c" - fat32 lba
				    w - write changes to disk

Make sure kernel is not using "old partition table" (you may get a warning) and continue:
You may need to run "sudo fdisk -l" again. I'll be using /dev/sde

You need min 4GB flash drvie for >>modern<< utitlities to apply FAT32 correctly


sudo mkfs.fat /dev/sde1 -F 32

comment 2

sudo umount /dev/sde1

comment 3

sudo dd if=geppy/boot/mbr.bin of=/dev/sde conv=fdatasync

comment 4

sudo dd if=geppy/boot/jump.bin of=/dev/sde1 conv=fdatasync

comment 5

sudo dd if=geppy/boot/vbr_fat32.bin of=/dev/sde1 obs=1c seek=90 conv=fdatasync

replug your drive/disk and copy geppy.img

# License

Well, It's GPL v1.
Will change if anyone interested in active help.
