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
; heads and sectors per track from the first used partition entry they
; can be worked out from exactly: the geometry under which the entry's
; start CHS gives its start LBA and its end CHS gives its end LBA
; (start + size - 1). This holds whether the partition was made by DOS
; FDISK (0/1/1, ending on a cylinder boundary) or by a later tool (1 MiB
; aligned, ending anywhere). An end CHS clamped at cylinder 1023 gives
; the heads as end head + 1. Cylinders then come from the drive's sector
; count. Drives without a usable entry keep the XLATE_MODE_RIVET
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
	; restore if none can be worked out
	push	WORD [di+DPT.wLHeads]
	push	WORD [di+DPT.bLSect]
	mov		si, BOOTVARS.rgbBootSect+446	; ES:SI to first partition entry
.EntryLoop:
	call	AutoXlate_GeometryFromEntryAtESSI
	jnc		SHORT .GeometryFound
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


;--------------------------------------------------------------------
; Puts the heads and sectors per track worked out from a partition
; entry in the DPT (see AutoXlate_FromPartitionTables). Each head count
; from 1 up is tried: the start CHS and start LBA then give the sectors
; per track, exactly, and the end CHS must give the end LBA. If both
; start and end are at head 0, only heads * SPT is fixed; trying the
; smallest head count first then gives the largest SPT up to 63.
;
; AutoXlate_GeometryFromEntryAtESSI
;	Parameters:
;		DS:DI:	Ptr to DPT
;		ES:SI:	Ptr to partition entry
;	Returns:
;		CF:		Cleared if wLHeads and bLSect are set from the entry
;				Set if the entry can't be used (DPT geometry trashed)
;	Corrupts registers:
;		AX, BX, CX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
AutoXlate_GeometryFromEntryAtESSI:
	cmp		BYTE [es:si+4], 0				; Unused entry?
	je		SHORT .NotUsable
	mov		ax, [es:si+2]					; Start sector and cylinder
	or		ax, [es:si+6]					; End sector and cylinder
	test	ax, 0FFC0h
	jz		SHORT .NotUsable				; All in cylinder 0: heads unknown
	mov		WORD [di+DPT.wLHeads], 0
.NextHeads:
	inc		BYTE [di+DPT.wLHeads]			; Up to 255, then wraps to 0
	jnz		SHORT .TryHeads
.NotUsable:
	stc
	ret

	; Sectors per track from the start:
	; start LBA - start sector + 1 = (cylinder * heads + head) * SPT
.TryHeads:
	mov		cl, [es:si+2]					; Start sector and cylinder 9...8
	mov		ch, [es:si+3]					; Start cylinder 7...0
	mov		dh, [es:si+1]					; Start head
	call	HAddress_ExtractLCHSFromBiosParams	; BL=Sector, BH=Head, CX=Cylinder
	mov		ax, [di+DPT.wLHeads]
	cmp		bh, al
	jae		SHORT .NextHeads				; Start head past the cylinder
	mul		cx								; DX:AX = Cylinder * heads
	add		al, bh
	adc		ah, 0
	adc		dx, BYTE 0
	jnz		SHORT .NextHeads				; Too large for a 16-bit divisor
	xchg	cx, ax							; CX = Cylinder * heads + head
	jcxz	.NextHeads
	xor		bh, bh
	dec		bx								; BX = Start sector - 1
	mov		ax, [es:si+8]
	mov		dx, [es:si+10]
	sub		ax, bx
	sbb		dx, BYTE 0
	jb		SHORT .NextHeads
	cmp		dx, cx
	jae		SHORT .NextHeads				; Quotient over 16 bits
	div		cx								; AX = Sectors per track
	test	dx, dx
	jnz		SHORT .NextHeads
	cmp		ax, BYTE 63
	ja		SHORT .NextHeads
	cmp		bl, al
	jae		SHORT .NextHeads				; Start sector 0 or past the track
	mov		[di+DPT.bLSect], al

	; End CHS clamped at cylinder 1023: heads must be end head + 1
	mov		ax, [es:si+6]
	and		al, 0C0h
	cmp		ax, 0FFC0h
	jne		SHORT .CheckEnd
	mov		al, [es:si+5]
	inc		al
	cmp		al, [di+DPT.wLHeads]
	jne		SHORT .NextHeads
	ret										; CF cleared

.NextHeadsFromEnd:
	jmp		SHORT .NextHeads

	; Otherwise the end CHS must give the end LBA
.CheckEnd:
	mov		cl, [es:si+6]					; End sector and cylinder 9...8
	mov		ch, [es:si+7]					; End cylinder 7...0
	mov		dh, [es:si+5]					; End head
	call	HAddress_ExtractLCHSFromBiosParams
	cmp		bh, [di+DPT.wLHeads]
	jae		SHORT .NextHeadsFromEnd
	test	bl, bl
	jz		SHORT .NextHeadsFromEnd
	cmp		bl, [di+DPT.bLSect]
	ja		SHORT .NextHeadsFromEnd
	call	HAddress_ConvertLCHStoLBA28		; DX:AX = End LBA with this geometry
	sub		ax, [es:si+8]
	sbb		dx, [es:si+10]
	add		ax, BYTE 1
	adc		dx, BYTE 0						; DX:AX = Size with this geometry
	cmp		ax, [es:si+12]
	jne		SHORT .NextHeadsFromEnd
	cmp		dx, [es:si+14]
	jne		SHORT .NextHeadsFromEnd
	ret										; CF cleared
