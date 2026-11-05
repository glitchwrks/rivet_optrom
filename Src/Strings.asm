; File name		:	Strings.asm
; Project name	:	IDE BIOS
; Created date	:	4.12.2007
; Last update	:	9.4.2010
; Author		:	Tomi Tilli
; Modified		:	2026 by Glitch Works, LLC for Rivet (see git history)
; Description	:	Strings and equates for BIOS messages.

; Section containing code
SECTION .text

; POST drive detection strings
g_szRomAt:		db	"%s @ %x",CR,LF,STOP
g_szMaster:		db	"Master",STOP
g_szSlave:		db	"Slave ",STOP
g_szDetect:		db	"IDE %s at %x: ",STOP			; IDE Master at 1F0h:
g_szNotFound:	db	"not found",CR,LF,STOP

; Boot loader strings
%ifdef MODULE_BOOT_MENU
g_szFloppyDrv:	db	"Floppy Drive",STOP
g_szHardDrv:	db	" Hard Drive ",STOP
g_szTryToBoot:	db	"Booting from %s %x",175,"%x ... ",STOP
g_szBootSector:	db	"Boot Sector",STOP
g_szFound:		db	"found",STOP
g_szSectRead:	db	"%s %s!",CR,LF,STOP
g_szReadError:	db	"Error %x!",CR,LF,STOP
%else	; Without the Boot Menu, only hard disk boot failures are printed
g_szHdReadError:	db	"Can't boot hard disk %x: error %x",CR,LF,STOP
g_szHdNotBootable:	db	"Can't boot hard disk %x: no boot sector",CR,LF,STOP
%endif
%ifdef MODULE_BOOT_MENU	; Strings only used by the Boot Menu
g_sz18hCallback:db	"Boot menu callback via INT 18h",STOP

; Boot menu bottom of screen strings
g_szFDD:		db	"FDD",STOP
g_szHDD:		db	"HDD",STOP
g_szBottomScrn:	db	"%c to %c boots from %s with %s mappings",CR,LF,STOP

; Boot Menu bottom border string
g_szTimeout:	db	"Selection Timeout ",STOP

%endif ; MODULE_BOOT_MENU

; Boot Menu title strings. Kept in every image, so the original copyright
; notice stays in the ROM even when the Boot Menu is not included.
g_szTitleLn3:	db	"Copyright 2009-2010 by Tomi Tilli",STOP

%ifdef MODULE_BOOT_MENU

; Boot Menu menuitem strings
g_szFDLetter:	db	"%s %c",STOP
g_szforeignHD:	db	"Foreign Hard Disk",STOP
g_szRomBoot:	db	"ROM Boot",STOP

; Boot Menu information strings
g_szCapacity:	db	"Capacity : ",STOP
g_szSizeSingle:	db	"%s%u.%u %ciB",STOP
g_szSizeDual:	db	"%s%u.%u %ciB / %u.%u %ciB",STOP
g_szCfgHeader:	db	"Addr.", T_V, "Block", T_V, "Bus",   T_V, "IRQ",   T_V, "Reset", STOP
g_szCfgFormat:	db	"%s"   , T_V, "%5u",   T_V, "%c%2u", T_V, " %c%c", T_V, "%5x",   STOP
g_szLCHS:		db	"L-CHS",STOP
g_szPCHS:		db	"P-CHS",STOP
g_szLBA28:		db	"LBA28",STOP
g_szLBA48:		db	"LBA48",STOP
g_szFddUnknown:	db	"%sUnknown",STOP
g_szFddSizeOr:	db	"%s5",172,22h," or 3",171,22h," DD",STOP
g_szFddSize:	db	"%s%c%c",22h,", %u kiB",STOP	; 3½", 1440 kiB
%endif ; MODULE_BOOT_MENU
