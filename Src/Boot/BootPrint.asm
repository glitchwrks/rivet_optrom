; File name		:	BootPrint.asm
; Project name	:	IDE BIOS
; Created date	:	19.3.2010
; Last update	:	1.4.2010
; Author		:	Tomi Tilli
; Modified		:	2026 by Glitch Works, LLC for Rivet (see git history)
; Description	:	Functions for printing boot related strings.

; Section containing code
SECTION .text

%ifdef MODULE_BOOT_MENU

;--------------------------------------------------------------------
; Prints trying to boot string.
;
; BootPrint_TryToBootFromDL
;	Parameters:
;		DL:		Drive to boot from (translated, 00h or 80h)
;		DS:		RAMVARS segment
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootPrint_TryToBootFromDL:
	push	dx
	ePUSH_T	ax, BootPrint_PopDxAndReturn	; Return address

	xor		dh, dh				; Translated drive number to DX
	push	dx					; Push translated drive number
%ifdef MODULE_BOOT_MENU			; (no translation without Boot Menu)
	call	DriveXlate_ToOrBack
%endif
	push	dx					; Push untranslated drive number

	mov		ax, g_szFloppyDrv	; Assume "Floppy Drive"
	test	dl, 80h				; Hard Disk?
	jz		SHORT .PushHardOrFloppy
	add		ax, BYTE g_szHardDrv - g_szFloppyDrv
.PushHardOrFloppy:
	push	ax

	mov		si, g_szTryToBoot
	mov		dh, 6				; 6 bytes pushed to stack
	jmp		PrintString_JumpToFormat

ALIGN JUMP_ALIGN
BootPrint_PopDxAndReturn:
	pop		dx
	ret


;--------------------------------------------------------------------
; Prints message that valid boot sector has been found.
;
; BootPrint_BootSectorLoaded
;	Parameters:
;		Nothing
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX, SI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootPrint_BootSectorLoaded:
	push	dx
	ePUSH_T	ax, BootPrint_PopDxAndReturn	; Return address

	ePUSH_T	ax, g_szFound
	ePUSH_T	ax, g_szBootSector
	mov		si, g_szSectRead
	mov		dh, 4							; 4 bytes pushed to stack
	jmp		PrintString_JumpToFormat


;--------------------------------------------------------------------
; Prints message that first sector is not boot sector.
;
; BootPrint_FirstSectorNotBootable
;	Parameters:
;		Nothing
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX, DX, SI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootPrint_FirstSectorNotBootable:
	ePUSH_T	ax, g_szNotFound
	ePUSH_T	ax, g_szBootSector
	mov		si, g_szSectRead
	mov		dh, 4				; 4 bytes pushed to stack
	jmp		PrintString_JumpToFormat


;--------------------------------------------------------------------
; Prints error code for failed first sector read attempt.
;
; BootPrint_FailedToLoadFirstSector
;	Parameters:
;		AH:		INT 13h error code
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX, DX, SI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootPrint_FailedToLoadFirstSector:
	eMOVZX	cx, ah				; Error code to CX
	push	cx					; Push INT 13h error code
	mov		si, g_szReadError
	mov		dh, 2				; 2 bytes pushed to stack
	jmp		PrintString_JumpToFormat

%else ; No Boot Menu

; Without the Boot Menu the image boots like a stock BIOS: silently from
; A: if it holds a bootable disk, otherwise from the first hard disk. The
; only message is for a hard disk that can't be booted, since otherwise
; the system would drop into INT 18h (ROM BASIC on IBM machines) with no
; hint why. A floppy failure is normal (empty drive) and isn't reported.

;--------------------------------------------------------------------
; Prints why the first sector could not be loaded, for hard disks only.
;
; BootPrint_FailedToLoadFirstSector
;	Parameters:
;		AH:		INT 13h error code
;		DL:		Drive number
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX, SI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootPrint_FailedToLoadFirstSector:
	test	dl, 80h						; Floppy drive?
	jz		SHORT BootPrint_Return		;  If so, nothing to print
	eMOVZX	cx, ah						; Error code to CX (before ePUSH_T)
	push	dx
	ePUSH_T	ax, BootPrint_PopDxAndReturn	; Return address
	push	cx							; Push INT 13h error code
	mov		si, g_szHdReadError
	mov		cl, 4						; Drive + error code pushed
	jmp		SHORT BootPrint_PushDriveFromDLandFormatSI

;--------------------------------------------------------------------
; Prints that the hard disk has no boot sector.
;
; BootPrint_FirstSectorNotBootable
;	Parameters:
;		DL:		Drive number (hard disk)
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX, SI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootPrint_FirstSectorNotBootable:
	push	dx
	ePUSH_T	ax, BootPrint_PopDxAndReturn	; Return address
	mov		si, g_szHdNotBootable
	mov		cl, 2						; Drive pushed
	; Fall to BootPrint_PushDriveFromDLandFormatSI

BootPrint_PushDriveFromDLandFormatSI:
	xor		dh, dh
	push	dx							; Push drive number
	mov		dh, cl						; Number of bytes pushed
	jmp		PrintString_JumpToFormat

ALIGN JUMP_ALIGN
BootPrint_PopDxAndReturn:
	pop		dx
BootPrint_Return:
	ret

%endif ; MODULE_BOOT_MENU
