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
	eMOVZX	cx, BYTE [RAMVARS.bDrvCnt]
	jcxz	.Return
	mov		dl, [RAMVARS.bFirstDrv]
.DriveLoop:
	push	cx
	push	dx
	call	AutoXlate_ForDriveInDL
	pop		dx
	pop		cx
	inc		dx
	loop	.DriveLoop
.Return:
	ret


;--------------------------------------------------------------------
; AutoXlate_ForDriveInDL
;	Parameters:
;		DL:		Drive number (one of ours)
;		DS:		RAMVARS segment
;		ES:		BDA segment (zero)
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
AutoXlate_ForDriveInDL:
	call	FindDPT_ForDriveNumber			; DS:DI now points to DPT
	jnc		SHORT .Return
	test	BYTE [di+DPT.bFlags], FLG_DPT_LBAXLATE
	jz		SHORT .Return					; No LBA, keep default geometry
	call	AccessDPT_GetPointerToDRVPARAMStoCSBX
	cmp		BYTE [cs:bx+DRVPARAMS.bXlateMode], XLATE_MODE_AUTO
	jne		SHORT .Return

	; Read MBR to 0000:7C00h. Sector 0 is at CHS 0/0/1 whatever the
	; geometry, and the drive is already using LBA addressing.
	push	dx
	mov		bx, BOOTVARS.rgbBootSect
	mov		ax, 0201h						; Read 1 sector
	mov		cx, 1							; Cylinder 0, sector 1
	xor		dh, dh							; Head 0
	int		INTV_DISK_FUNC
	pop		dx
	jc		SHORT .Return
	call	FindDPT_ForDriveNumber			; DS:DI to DPT again
	cmp		WORD [es:BOOTVARS.rgbBootSect+510], 0AA55h
	jne		SHORT .Return

	mov		si, BOOTVARS.rgbBootSect+446	; ES:SI to first partition entry
	mov		cx, 4
.EntryLoop:
	cmp		BYTE [es:si+4], 0				; Unused entry?
	je		SHORT .NextEntry
	push	cx
	call	AutoXlate_TryPartitionEntryInESSI
	pop		cx
	jnc		SHORT .Return					; Geometry taken from this entry
.NextEntry:
	add		si, BYTE 16
	loop	.EntryLoop
.Return:
	ret


;--------------------------------------------------------------------
; Takes L-CHS geometry from a partition table entry if it is consistent.
;
; AutoXlate_TryPartitionEntryInESSI
;	Parameters:
;		DL:		Drive number
;		DS:DI:	Ptr to DPT
;		ES:SI:	Ptr to partition table entry
;	Returns:
;		CF:		Cleared if geometry stored to DPT
;				Set if entry not usable (DPT unchanged)
;	Corrupts registers:
;		AX, BX, CX
;--------------------------------------------------------------------
AutoXlate_ReturnEntryNotUsable:
	stc
	ret
ALIGN JUMP_ALIGN
AutoXlate_TryPartitionEntryInESSI:
	; Heads and sectors per track from the end CHS
	mov		cl, [es:si+5]					; End head
	inc		cl								; CL = Heads
	jz		SHORT AutoXlate_ReturnEntryNotUsable	; 256 heads not allowed
	mov		ch, [es:si+6]
	and		ch, 3Fh							; CH = Sectors per track
	jz		SHORT AutoXlate_ReturnEntryNotUsable
	push	dx

	; Cylinders = sector count / (heads * sectors per track), max 1024
	call	BootInfo_GetOffsetToBX			; ES:BX to BOOTNFO for the drive
	push	cx
	mov		al, cl
	mul		ch
	xchg	cx, ax							; CX = Sectors per cylinder
	mov		ax, 1024
	cmp		WORD [es:bx+BOOTNFO.twSectCnt+4], BYTE 0
	jne		SHORT .CylindersInAX			; 48-bit sector count
	mov		dx, [es:bx+BOOTNFO.twSectCnt+2]
	cmp		dx, cx
	jae		SHORT .CylindersInAX			; Over 65535 cylinders
	mov		ax, [es:bx+BOOTNFO.twSectCnt]
	div		cx								; AX = Cylinders
	MIN_U	ax, 1024
.CylindersInAX:
	pop		cx								; CL = Heads, CH = Sectors per track
	test	ax, ax
	jz		SHORT .PopDXandEntryNotUsable	; Smaller than one cylinder

	; Try the geometry: store to DPT, keeping the old values to restore
	push	ax
	push	WORD [di+DPT.wLHeads]
	push	WORD [di+DPT.bLSect]
	mov		[di+DPT.bLSect], ch
	xor		ch, ch
	mov		[di+DPT.wLHeads], cx

	; Start CHS must give the start LBA with this geometry. Partitions
	; starting at cylinder 1023 (or later) can't be checked.
	mov		cl, [es:si+2]					; Start sector and cylinder 9...8
	mov		ch, [es:si+3]					; Start cylinder 7...0
	mov		dh, [es:si+1]					; Start head
	call	HAddress_ExtractLCHSFromBiosParams	; BL=Sector, BH=Head, CX=Cylinder
	cmp		cx, 1023
	jae		SHORT .RestoreGeometry
	test	bl, bl
	jz		SHORT .RestoreGeometry			; Sector 0 is not valid
	cmp		bl, [di+DPT.bLSect]
	ja		SHORT .RestoreGeometry
	cmp		bh, [di+DPT.wLHeads]
	jae		SHORT .RestoreGeometry
	call	HAddress_ConvertLCHStoLBA28		; DX:AX = Start LBA
	cmp		ax, [es:si+8]
	jne		SHORT .RestoreGeometry
	cmp		dx, [es:si+10]
	jne		SHORT .RestoreGeometry

	; Consistent: keep heads and sectors, store cylinders
	add		sp, BYTE 4						; Drop saved geometry
	pop		WORD [di+DPT.wLCyls]
	pop		dx
	clc
	ret

.RestoreGeometry:
	pop		WORD [di+DPT.bLSect]
	pop		WORD [di+DPT.wLHeads]
	pop		ax								; Drop cylinders
.PopDXandEntryNotUsable:
	pop		dx
	stc
	ret
