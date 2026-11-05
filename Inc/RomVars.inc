; File name		:	RomVars.inc
; Project name	:	IDE BIOS
; Created date	:	23.3.2010
; Last update	:	1.5.2010
; Author		:	Tomi Tilli
; Modified		:	2026 by Glitch Works, LLC for Rivet (see git history)
; Description	:	Defines for ROMVARS struct containing variables stored
;					in BIOS ROM.
%ifndef ROMVARS_INC
%define ROMVARS_INC

; ROM Variables. There are written to ROM image before flashing.
struc ROMVARS
	.wRomSign		resb	2	; ROM Signature (AA55h)
	.bRomSize		resb	1	; ROM size in 512 byte blocks
	.rgbJump		resb	5	; First instruction to ROM init (jmp)
	; Offset 8 (8h) starts here
	.rgbDate		resb	8	; BIOS build date string (mm/dd/yy)
	; Offset 16 (10h) starts here
	.rgbSign		resb	8	; Signature for configuration program
	.szTitle		resb	31	; BIOS title string
	.szVersion		resb	25	; BIOS version string
	; Offset 80 (50h) starts here
	.wFlags			resb	2	; Word for ROM flags
	.bIdeCnt		resb	1	; Number of supported IDE controllers
	.bBootDrv		resb	1	; Boot Menu default drive
	.bBootMnuH		resb	1	; Boot Menu maximum height
	.bBootDelay		resb	1	; Boot Menu selection delay in seconds
	.bBootLdrType	resb	1	; Boot Loader type
	.bMinFddCnt		resb	1	; Minimum number of Floppy Drives
	.bStealSize		resb	1	; Number of 1kB blocks stolen from 640kB base RAM
	.wBuildFlags	resb	2	; What this image was built with (read only, see below)
					resb	5
	; Offset 96 (60h) starts here
	; Last IDEVARS must not start after offset FFh.
	.ideVars0		resb	IDEVARS_size
	.ideVars1		resb	IDEVARS_size
	.ideVars2		resb	IDEVARS_size
	.ideVars3		resb	IDEVARS_size
	.ideVars4		resb	IDEVARS_size
endstruc

; Bit defines for ROMVARS.wFlags
FLG_ROMVARS_FULLMODE	EQU	(1<<0)	; Full operating mode (steals base RAM, supports EBIOS etc.)
FLG_ROMVARS_LATE		EQU	(1<<1)	; Late initialization
FLG_ROMVARS_DRVXLAT		EQU	(1<<2)	; Enable drive number translation
FLG_ROMVARS_ROMBOOT		EQU	(1<<3)	; Include ROMBOOT to boot menu
FLG_ROMVARS_DRVNFO		EQU	(1<<4)	; Display drive info on boot menu
FLG_ROMVARS_MAXSIZE		EQU	(1<<5)	; Maximize size by sacrificing compatibility with some old BIOSes

; Bit defines for ROMVARS.wBuildFlags. These describe how the image was
; built, so the configuration program can tell which settings apply to it.
; The configuration program must not change them. A bit is set when
; something was left out of the build, so zero means a full build (and
; images built before this field existed, where it was reserved, read
; correctly as full builds).
FLG_BUILD_NOBOOTMENU	EQU	(1<<0)	; Built without the Boot Menu (BOOTLOADER_TYPE_MENU
								; falls back to BOOTLOADER_TYPE_SIMPLE; bBootDrv,
								; bBootMnuH, bBootDelay, FLG_ROMVARS_ROMBOOT,
								; FLG_ROMVARS_DRVNFO and FLG_ROMVARS_DRVXLAT are
								; not used)

; Bootloader types for ROMVARS.bBootLdrType
BOOTLOADER_TYPE_MENU	EQU	(0<<1)	; Display boot menu on boot loader
BOOTLOADER_TYPE_SIMPLE	EQU	(1<<1)	; Simple bootloader without menu
BOOTLOADER_TYPE_NONE	EQU	(3<<1)	; Do not install boot loader


; Controller specific variables
struc IDEVARS
	.wPort				resb	2	; IDE Base Port for Command Block (usual) Registers
	.wPortCtrl			resb	2	; IDE Base Port for Control Block Registers
	.bBusType			resb	1	; Bus type
	.bIRQ				resb	1	; Interrupt Request Number
						resb	4	; Reserved
	.drvParamsMaster	resb	DRVPARAMS_size
	.drvParamsSlave		resb	DRVPARAMS_size
endstruc

; Bus types for IDEVARS.bBusType
BUS_TYPE_8_DUAL			EQU	(0<<1)	; XTIDE transfers with two 8-bit data ports
BUS_TYPE_16				EQU	(1<<1)	; Normal 16-bit AT-IDE transfers
BUS_TYPE_32				EQU	(2<<1)	; 32-bit VLB and PCI transfers
BUS_TYPE_8_SINGLE		EQU	(3<<1)	; 8-bit transfers with single 8-bit data port
BUS_TYPE_8_HISPEED		EQU	(4<<1)	; XTIDE HI-SPEED mode (A0 and A3 swapped, "Chuck mod")


; Master/Slave drive specific parameters
struc DRVPARAMS
	.wFlags			resb	2	; Drive flags
	.bXlateMode		resb	1	; CHS translation mode (XLATE_MODE_xxx)
					resb	1	; Reserved
	.wCylinders		resb	2	; User specified cylinders (1...16383)
	.wSectAndHeads:
	.bSect			resb	1	; User specified Sectors per track (1...63)
	.bHeads			resb	1	; User specified Heads (1...16)
endstruc

; Bit defines for DRVPARAMS.wFlags
FLG_DRVPARAMS_USERCHS	EQU	(1<<0)	; User specified P-CHS values
FLG_DRVPARAMS_BLOCKMODE	EQU	(1<<1)	; Enable Block mode transfers

; CHS translation modes for DRVPARAMS.bXlateMode: how the L-CHS geometry
; that INT 13h reports (and DOS partitions and formats with) is made from
; the drive. What matters for exchanging disks between machines is the
; heads and sectors per track. The LBA modes need a drive that supports
; LBA and no user specified CHS; otherwise XLATE_MODE_RIVET is used.
XLATE_MODE_RIVET		EQU	0	; XTIDE Universal BIOS v1.1.5: halve cylinders and
								; double heads until 1024 or less (256 -> 255 heads)
XLATE_MODE_NONE			EQU	1	; No translation ("Normal"): P-CHS, max 1024 cylinders
XLATE_MODE_LBA_ASSIST	EQU	2	; LBA assist above 1024 cylinders: 63 sectors, heads
								; 16/32/64/128/255 by capacity (XUB 2.x since r610,
								; 486-era "LBA" BIOS setting)
XLATE_MODE_LBA_255		EQU	3	; Always 255 heads, 63 sectors (later PCs)
XLATE_MODE_LAST			EQU	XLATE_MODE_LBA_255


%endif ; ROMVARS_INC
