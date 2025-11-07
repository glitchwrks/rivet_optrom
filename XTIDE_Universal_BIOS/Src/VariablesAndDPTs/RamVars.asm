; Project name	:	XTIDE Universal BIOS
; Description	:	Functions for accessings RAMVARS.

;
; XTIDE Universal BIOS and Associated Tools
; Copyright (C) 2009-2010 by Tomi Tilli, 2011-2025 by XTIDE Universal BIOS Team.
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
; Initializes RAMVARS.
; Drive detection can be started after this function returns.
;
; RamVars_Initialize
;	Parameters:
;		Nothing
;	Returns:
;		DS:		RAMVARS segment
;	Corrupts registers:
;		AX, CX, DX, DI
;--------------------------------------------------------------------
RamVars_Initialize:
	push	es

	mov		ax, [cs:ROMVARS.wRamVars]
	test	ax, ax						; UMB segment or LITE_MODE_RAMVARS_SEGMENT?
	jnz		SHORT .InitializeRamvars	; No need to steal RAM

	mov		ds, ax
	mov		al, [cs:ROMVARS.bStealSize]
	sub		[BDA.wBaseMem], ax
%ifdef USE_186
	imul	ax, [BDA.wBaseMem], 64
%else
	mov		al, 64
	mul		WORD [BDA.wBaseMem]
%endif

.InitializeRamvars:
	xor		di, di
	mov		ds, ax
	mov		es, ax
	mov		cx, RAMVARS_size
	call	Memory_ZeroESDIwithSizeInCX
	mov		WORD [RAMVARS.wDrvDetectSignature], RAMVARS_DRV_DETECT_SIGNATURE
	mov		WORD [RAMVARS.wSignature], RAMVARS_RAM_SIGNATURE
%ifdef MODULE_DRIVEXLATE
	call	DriveXlate_Reset
%endif

	pop		es
	ret


;--------------------------------------------------------------------
; Returns segment to RAMVARS.
; RAMVARS might be located at the top of interrupt vectors (0030:0000h),
; at the top of system base RAM or in a user configured UMB.
;
; RamVars_GetSegmentToDS
;	Parameters:
;		Nothing
;	Returns:
;		DS:		RAMVARS segment
;	Corrupts registers:
;		DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
RamVars_GetSegmentToDS:
	mov		ds, [cs:ROMVARS.wRamVars]
	mov		di, ds
	test	di, di					; UMB segment or LITE_MODE_RAMVARS_SEGMENT?
	jnz		SHORT .Return

;%ifdef USE_186
;	imul	di, [BDA.wBaseMem], 64	; 2 bytes less but slower, especially on 386/486 processors
;%else
	mov		di, [BDA.wBaseMem]		; Load available base memory size in kB
	eSHL_IM	di, 6					; Segment to first stolen kB (*=40h)
;%endif
ALIGN JUMP_ALIGN
.LoopStolenKBs:
	mov		ds, di					; EBDA segment to DS
	add		di, BYTE 64				; DI to next stolen kB
	cmp		WORD [RAMVARS.wSignature], RAMVARS_RAM_SIGNATURE
	jne		SHORT .LoopStolenKBs	; Loop until sign found (always found eventually)
.Return:
	ret


;--------------------------------------------------------------------
; RamVars_GetHardDiskCountFromBDAtoAX
;	Parameters:
;		DS:		RAMVARS segment
;	Returns:
;		AX:		Total hard disk count
;	Corrupts registers:
;		BX
;--------------------------------------------------------------------
%ifdef MODULE_BOOT_MENU
RamVars_GetHardDiskCountFromBDAtoAX:
	call	RamVars_GetCountOfKnownDrivesToAX
	push	ds
	LOAD_BDA_SEGMENT_TO	ds, bx
	mov		bl, [BDA.bHDCount]
	MAX_U	al, bl
	pop		ds
	ret
%endif


%ifdef MODULE_SERIAL_FLOPPY
;--------------------------------------------------------------------
; RamVars_UnpackFlopCntAndFirstToAL
;	Parameters:
;		DS:		RAMVARS segment
;	Returns:
;		AL:		First floppy drive number supported
;		CF:		Number of floppy drives supported (clear = 1, set = 2)
;		SF:		Emulating drives (clear = yes, set = no)
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
RamVars_UnpackFlopCntAndFirstToAL:
	mov		al, [RAMVARS.xlateVars+XLATEVARS.bFlopCntAndFirst]
	sar		al, 1
	ret
%endif


;--------------------------------------------------------------------
; RamVars_GetIdeControllerCountToCX
;	Parameters:
;		Nothing
;	Returns:
;		CX:		Number of IDE controllers to handle
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
RamVars_GetIdeControllerCountToCX:
	eMOVZX	cx, BYTE [cs:ROMVARS.bIdeCnt]
	ret


;--------------------------------------------------------------------
; RamVars_GetCountOfKnownDrivesToAX
;	Parameters:
;		DS:		RAMVARS segment
;	Returns:
;		AX:		Total hard disk count
;	Corrupts registers:
;		None
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
RamVars_GetCountOfKnownDrivesToAX:
	mov		ax, [RAMVARS.wFirstDrvAndCount]
	add		al, ah
	and		ax, BYTE 7Fh
	ret
