; File name		:	AutoXlate.asm
; Project name	:	Rivet
; Created date	:	4.11.2026
; Author		:	Glitch Works, LLC
; Description	:	XLATE_MODE_AUTO: L-CHS geometry taken from the drive's
;					partition table.
;
; Rivet option ROM
; Copyright (C) 2026 Glitch Works, LLC
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License, version 2, as
; published by the Free Software Foundation.
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.

; Section containing code
SECTION .text

;--------------------------------------------------------------------
; For drives using XLATE_MODE_AUTO, reads the MBR and takes the L-CHS
; heads and sectors per track from the partition table: the end CHS of
; a partition gives them (DOS ends partitions on a cylinder boundary),
; and the entry is only used if its start CHS gives its start LBA with
; that geometry. Cylinders then come from the drive's sector count.
; Drives without a usable partition table keep the XLATE_MODE_RIVET
; geometry set by CreateDPT_StoreLCHS.
;
; CreateDPT_StoreLCHS gives XLATE_MODE_AUTO drives LBA addressing
; (FLG_DPT_LBAXLATE) when possible, so only the geometry changes here.
; Must be called after the drives have been reset and before the
; compatible DPTs are created.
;
; AutoXlate_FromPartitionTables
;	Parameters:
;		DS:		RAMVARS segment
;		ES:		BDA segment (zero)
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
AutoXlate_FromPartitionTables:
	mov		si, AutoXlate_ForDPTinDSDI
	jmp		FindDPT_IterateAllDPTs


;--------------------------------------------------------------------
; FindDPT_IterateAllDPTs callback: must keep AH (zero), CX, SI and DI
; and return CF cleared to see every DPT.
;
; AutoXlate_ForDPTinDSDI
;	Parameters:
;		DS:DI:	Ptr to DPT
;		ES:		BDA segment (zero)
;	Returns:
;		CF:		Cleared
;	Corrupts registers:
;		AL, BX, DX
;--------------------------------------------------------------------
AutoXlate_ReturnWithCFcleared:
	ret
ALIGN JUMP_ALIGN
AutoXlate_ForDPTinDSDI:
	test	BYTE [di+DPT.bFlags], FLG_DPT_LBAXLATE
	jz		SHORT AutoXlate_ReturnWithCFcleared	; No LBA, keep default geometry
	call	AccessDPT_GetPointerToDRVPARAMStoCSBX
	mov		al, [cs:bx+DRVPARAMS.bXlateMode]
	xor		al, XLATE_MODE_AUTO				; Clears CF
	jnz		SHORT AutoXlate_ReturnWithCFcleared
	push	ax
	push	cx
	push	si
	push	di

	; Read MBR to 0000:7C00h. Sector 0 is at CHS 0/0/1 whatever the
	; geometry, and the drive is already using LBA addressing.
	mov		dl, [di+DPT.bDrvNum]
	mov		bx, BOOTVARS.rgbBootSect
	mov		ax, 0201h						; Read 1 sector
	mov		cx, 1							; Cylinder 0, sector 1
	xor		dh, dh							; Head 0
	int		INTV_DISK_FUNC
	pop		di								; DS:DI to DPT again
	push	di
	jc		SHORT .PopAndReturn
	cmp		WORD [es:BOOTVARS.rgbBootSect+510], 0AA55h
	jne		SHORT .PopAndReturn

	; Try each entry's geometry in the DPT, keeping the default to
	; restore if none is consistent
	push	WORD [di+DPT.wLHeads]
	push	WORD [di+DPT.bLSect]
	mov		si, BOOTVARS.rgbBootSect+446	; ES:SI to first partition entry
.EntryLoop:
	cmp		BYTE [es:si+4], 0				; Unused entry?
	je		SHORT .NextEntry
	mov		cl, [es:si+5]					; End head
	inc		cl								; CL = Heads
	jz		SHORT .NextEntry				; 256 heads not allowed
	mov		ch, [es:si+6]
	and		ch, 3Fh							; CH = Sectors per track
	jz		SHORT .NextEntry
	mov		[di+DPT.bLSect], ch
	xor		ch, ch
	mov		[di+DPT.wLHeads], cx

	; Start CHS must give the start LBA with this geometry. Entries
	; with CHS values out of range, or clamped at cylinder 1023, give
	; some other LBA.
	mov		cl, [es:si+2]					; Start sector and cylinder 9...8
	mov		ch, [es:si+3]					; Start cylinder 7...0
	mov		dh, [es:si+1]					; Start head
	call	HAddress_ExtractLCHSFromBiosParams	; BL=Sector, BH=Head, CX=Cylinder
	call	HAddress_ConvertLCHStoLBA28		; DX:AX = Start LBA
	cmp		ax, [es:si+8]
	jne		SHORT .NextEntry
	cmp		dx, [es:si+10]
	je		SHORT .GeometryFound
.NextEntry:
	add		si, BYTE 16
	cmp		si, BOOTVARS.rgbBootSect+510
	jb		SHORT .EntryLoop
.RestoreGeometry:
	pop		WORD [di+DPT.bLSect]
	pop		WORD [di+DPT.wLHeads]
.PopAndReturn:
	pop		di
	pop		si
	pop		cx
	pop		ax
	clc
	ret

	; Cylinders = sector count / (heads * sectors per track), max 1024
.GeometryFound:
	mov		dl, [di+DPT.bDrvNum]
	call	BootInfo_GetOffsetToBX			; ES:BX to BOOTNFO for the drive
	mov		al, [di+DPT.bLSect]
	mul		BYTE [di+DPT.wLHeads]			; AX = Sectors per cylinder
	xchg	cx, ax
	mov		ax, 1024
	cmp		WORD [es:bx+BOOTNFO.twSectCnt+4], BYTE 0
	jne		SHORT .StoreCylinders			; 48-bit sector count
	mov		dx, [es:bx+BOOTNFO.twSectCnt+2]
	cmp		dx, cx
	jae		SHORT .StoreCylinders			; Over 65535 cylinders
	mov		ax, [es:bx+BOOTNFO.twSectCnt]
	div		cx								; AX = Cylinders
	test	ax, ax
	jz		SHORT .RestoreGeometry			; Smaller than one cylinder
	MIN_U	ax, 1024
.StoreCylinders:
	mov		[di+DPT.wLCyls], ax
	pop		ax								; Drop saved geometry
	pop		ax
	jmp		SHORT .PopAndReturn
