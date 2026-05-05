; Project name	:	XTIDE Universal BIOS
; Description	:	Reading and jumping to boot sector.

;
; XTIDE Universal BIOS and Associated Tools
; Copyright (C) 2009-2010 by Tomi Tilli, 2011-2026 by XTIDE Universal BIOS Team.
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
; Visit http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
;

; Section containing code
SECTION .text

;--------------------------------------------------------------------
; BootSector_TryToLoadFromDriveDL_AndBoot
;	Parameters:
;		DL:		Drive to boot from (translated, 00h or 80h)
;		DS:		RAMVARS segment
;	Returns:
;		ES:BX:	Ptr to boot sector (if successful)
;		CF:		Cleared if boot sector loaded successfully
;				(only matters when jumping to
;				Int19h_JumpToBootSectorInESBXOrRomBoot)
;	Corrupts registers:
;		AX, CX, DH, SI, DI
;--------------------------------------------------------------------
BootSector_TryToLoadFromDriveDL_AndBoot:
	call	DetectPrint_TryToBootFromDL
	call	BootSector_LoadFirstSectorFromDriveDL
	jnc		SHORT .FirstSectorLoadedToESBX

	; Do not display timeout error (80h) for floppy drives since
	; it most likely mean no diskette in drive. This way we do not
	; display error code every time user intends to boot from hard disk
	; when A then C boot order is used.
	call	BootSector_DriveDLIsEmptyFloppydrive
	jz		SHORT BootSector_LoadFirstSectorFromDriveDL.Return
.PrintFailedToLoadErrorCode:
	jmp		DetectPrint_FailedToLoadFirstSector

.FirstSectorLoadedToESBX:
	test	dl, dl
	jns		SHORT Int19h_JumpToBootSectorInESBXOrRomBoot	; Don't check for boot sector signature for floppy booter games
	cmp		WORD [es:bx+510], 0AA55h						; Valid boot sector?
	je		SHORT Int19h_JumpToBootSectorInESBXOrRomBoot	; With CF cleared
	mov		si, g_szBootSectorNotFound
	jmp		DetectPrint_NullTerminatedStringFromCSSI


;--------------------------------------------------------------------
; BootSector_LoadFirstSectorFromDriveDL
;	Parameters:
;		DL:		Drive to boot from (translated, 00h or 80h)
;	Returns:
;		AH:		INT 13h error code
;		ES:BX:	Ptr to boot sector (if successful)
;		CF:		Cleared if read successful
;				Set if any error
;	Corrupts registers:
;		AL, CX, DH, DI
;--------------------------------------------------------------------
BootSector_LoadFirstSectorFromDriveDL:
	LOAD_BDA_SEGMENT_TO	es, bx				; ES:BX now points to...
	mov		bx, BOOTVARS.rgbBootSect		; ...boot sector location
	mov		di, BOOT_READ_RETRY_TIMES		; Initialize retry counter

.ReadRetryLoop:
	mov		ax, 0201h						; Read 1 sector
	mov		cx, 1							; Cylinder 0, Sector 1
	xor		dh, dh							; Head 0
	int		BIOS_DISK_INTERRUPT_13h
	jc		SHORT .FailedToLoadFirstSector
.Return:
	ret

.FailedToLoadFirstSector:
	dec		di								; Decrement retry counter (preserve CF)
	jz		SHORT .Return					; Loop while retries left

	; If the boot drive is a floppy drive and it is deemed to be empty then
	; we give up immediately to avoid unnecessarily long delays when booting.
	; This is particularly aggravating when using builds with first-A-then-C
	; boot order (i.e. non-interactive builds such as the Tiny build).
	call	BootSector_DriveDLIsEmptyFloppydrive
	jz		SHORT .Return					; With CF set

	; Reset drive and retry
	xor		ax, ax							; AH=00h, Disk Controller Reset
	test	dl, dl							; Floppy drive?
	eCMOVS	ah, RESET_HARD_DISK				; AH=0Dh, Reset Hard Disk (Alternate reset)
	int		BIOS_DISK_INTERRUPT_13h
	jmp		SHORT .ReadRetryLoop


;--------------------------------------------------------------------
; BootSector_DriveDLIsEmptyFloppydrive
;	Parameters:
;		AH:		INT 13h error code
;		DL:		Drive to boot from (translated, 00h or 80h)
;	Returns:
;		CF:		Set
;		ZF:		Set if DL is a floppy drive with no diskette inserted
;				Cleared if not
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
BootSector_DriveDLIsEmptyFloppydrive:
	test	dl, dl
	jnz		SHORT .Return					; Hard Drive
	cmp		ah, RET_HD_TIMEOUT
	je		SHORT .Return
	cmp		ah, RET_HD_NOMEDIA
.Return:
	stc
	ret

