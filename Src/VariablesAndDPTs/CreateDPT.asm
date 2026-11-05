; File name		:	CreateDPT.asm
; Project name	:	IDE BIOS
; Created date	:	12.3.2010
; Last update	:	26.4.2010
; Author		:	Tomi Tilli
; Modified		:	2026 by Glitch Works, LLC for Rivet (see git history)
; Description	:	Functions for creating Disk Parameter Table.

; Section containing code
SECTION .text

;--------------------------------------------------------------------
; Creates new Disk Parameter Table for detected hard disk.
; Drive is then fully accessible using any BIOS function.
;
; CreateDPT_FromAtaInformation
;	Parameters:
;		BH:		Drive Select byte for Drive and Head Register
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;		CS:BP:	Ptr to IDEVARS for the controller
;		DS:		RAMVARS segment
;		ES:		BDA Segment
;	Returns:
;		DL:		Drive number for new drive
;		DS:DI:	Ptr to Disk Parameter Table (if succesfull)
;		CF:		Cleared if DPT created successfully
;				Set if any error
;	Corrupts registers:
;		AX, CX, BX, DH
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_FromAtaInformation:
	call	FindDPT_ForNewDrive		; Get new DPT to DS:DI
	call	CreateDPT_Initialize
	call	CreateDPT_StoreDriveControlByte
	call	CreateDPT_StorePCHS
	call	CreateDPT_StoreLCHS
	call	CreateDPT_StoreAddressing
	call	CreateDPT_StoreBlockMode
	call	CreateDPT_StoreEBIOSSupport
	jmp		CreateDPT_StoreDriveNumberAndUpdateDriveCount


;--------------------------------------------------------------------
; Initializes empty DPT by storing initial values that are not
; read from ATA information.
;
; CreateDPT_Initialize
;	Parameters:
;		BH:		Drive Select byte for Drive and Head Register
;		DS:DI:	Ptr to Disk Parameter Table
;		CS:BP:	Ptr to IDEVARS for the controller
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_Initialize:
	xor		ax, ax						; Clear AX and CF
	mov		BYTE [di+DPT.bSize], DPT_size
	mov		BYTE [di+DPT.bDrvNum], al
	mov		BYTE [di+DPT.bFlags], al
	mov		BYTE [di+DPT.bReset], MASK_RESET_ALL
	mov		WORD [di+DPT.bIdeOff], bp
	mov		BYTE [di+DPT.bDrvSel], bh
	ret


;--------------------------------------------------------------------
; Stores Drive Control Byte for Device Control Register.
;
; CreateDPT_StoreDriveControlByte
;	Parameters:
;		BH:		Drive Select byte for Drive and Head Register
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;		CS:BP:	Ptr to IDEVARS for the controller
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		AX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StoreDriveControlByte:
	xor		ax, ax							; Zero AX
	cmp		BYTE [cs:bp+IDEVARS.bIRQ], 0	; Interrupts enabled?
	jne		SHORT .CheckHeadCount
	or		al, FLG_IDE_CTRL_nIEN			; Disable interrupts
ALIGN JUMP_ALIGN
.CheckHeadCount:
	cmp		BYTE [es:si+ATA1.wHeadCnt], 8	; 1...8 heads?
	jbe		SHORT .StoreDriveControlByte
	or		al, FLG_IDE_CTRL_O8H			; Over 8 heads (pre-ATA)
ALIGN JUMP_ALIGN
.StoreDriveControlByte:
	mov		[di+DPT.bDrvCtrl], al
	clc
	ret


;--------------------------------------------------------------------
; Stores P-CHS values from ATA information or user specified values to DPT.
;
; CreateDPT_StorePCHS
;	Parameters:
;		BH:		Drive Select byte for Drive and Head Register
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;		CS:BP:	Ptr to IDEVARS for the controller
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		AX, BX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StorePCHS:
	call	CreateDPT_GetUserOrAtaPCHS
	mov		[di+DPT.wPCyls], ax
	mov		[di+DPT.bPHeads], bh
	mov		[di+DPT.bPSect], bl
	clc
	ret

;--------------------------------------------------------------------
; Returns user specified P-CHS or values read from ATA information.
;
; CreateDPT_GetUserOrAtaPCHS
;	Parameters:
;		BH:		Drive Select byte for Drive and Head Register
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;		CS:BP:	Ptr to IDEVARS for the controller
;	Returns:
;		AX:		Number of P-CHS cylinders
;		BL:		Number of P-CHS sectors per track
;		BH:		Number of P-CHS heads
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_GetUserOrAtaPCHS:
	mov		ax, FLG_DRVPARAMS_USERCHS	; User specified CHS?
	call	AccessDPT_TestIdeVarsFlagsForMasterOrSlaveDrive
	jnz		SHORT CreateDPT_GetUserSpecifiedPCHS
	jmp		AtaID_GetPCHS

;--------------------------------------------------------------------
; Returns user specified P-CHS values from ROMVARS.
;
; CreateDPT_GetUserSpecifiedPCHS
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table
;		CS:BP:	Ptr to IDEVARS for the controller
;	Returns:
;		AX:		Number of user specified P-CHS cylinders
;		BL:		Number of user specified P-CHS sectors per track
;		BH:		Number of user specified P-CHS heads
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_GetUserSpecifiedPCHS:
	call	AccessDPT_GetPointerToDRVPARAMStoCSBX
	mov		ax, [cs:bx+DRVPARAMS.wCylinders]
	mov		bx, [cs:bx+DRVPARAMS.wSectAndHeads]
	or		BYTE [di+DPT.bFlags], FLG_DPT_USERCHS
	ret


;--------------------------------------------------------------------
; Stores L-CHS values (the geometry INT 13h reports) for the CHS
; translation mode selected for the drive (DRVPARAMS.bXlateMode).
;
; CreateDPT_StoreLCHS
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;		CS:BP:	Ptr to IDEVARS for the controller
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		AX, BX, CX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StoreLCHS:
	call	AccessDPT_GetPointerToDRVPARAMStoCSBX
	mov		al, [cs:bx+DRVPARAMS.bXlateMode]
	cmp		al, XLATE_MODE_NONE
	je		SHORT .NoTranslation
	jb		SHORT .ShiftPCHStoLCHS		; XLATE_MODE_RIVET
	cmp		al, XLATE_MODE_LAST
	ja		SHORT .ShiftPCHStoLCHS		; Unknown mode, use default

	; LBA modes need LBA addressing: not possible with user specified
	; P-CHS or if the drive does not support LBA.
	test	BYTE [di+DPT.bFlags], FLG_DPT_USERCHS
	jnz		SHORT .ShiftPCHStoLCHS
	test	WORD [es:si+ATA1.wCaps], A1_wCaps_LBA
	jz		SHORT .ShiftPCHStoLCHS
	cmp		al, XLATE_MODE_LBA_ASSIST
	jne		SHORT CreateDPT_StoreLbaTranslatedLCHSwith255Heads
	cmp		BYTE [di+DPT.bPHeads], 16
	ja		SHORT .ShiftPCHStoLCHS		; Invalid ATA ID, would overflow below
	cmp		BYTE [di+DPT.bPSect], 63
	ja		SHORT .ShiftPCHStoLCHS		; Invalid ATA ID, would overflow below
	cmp		WORD [di+DPT.wPCyls], 1024
	ja		SHORT CreateDPT_StoreLbaAssistedLCHS
	; Up to 1024 cylinders LBA assist does no translation, which is
	; what the default mode does too
	jmp		SHORT .ShiftPCHStoLCHS

	; XLATE_MODE_NONE: P-CHS as is, at most 1024 cylinders
.NoTranslation:
	mov		cx, [di+DPT.wPCyls]
	MIN_U	cx, 1024
	eMOVZX	dx, BYTE [di+DPT.bPHeads]
	xor		al, al
	jmp		SHORT .StoreSectorsPerTrack

	; XLATE_MODE_RIVET: v1.1.5 bit shift translation
.ShiftPCHStoLCHS:
	mov		cx, [di+DPT.wPCyls]			; P-CHS Cylinders (1...16383)
	eMOVZX	dx, BYTE [di+DPT.bPHeads]	; P-CHS Heads (1...16)
	call	CreateDPT_ShiftPCHtoLCH
	test	dh, dh						; 256 heads?
	jz		SHORT .StoreSectorsPerTrack	;  If less, no correction needed
	dec		dx							; Limit to 255 heads since DOS does not support 256 heads
.StoreSectorsPerTrack:
	mov		ah, [di+DPT.bPSect]			; L-CHS sectors per track = P-CHS
	mov		[di+DPT.bLSect], ah
CreateDPT_StoreLCHSfromCXDXwithShiftInAL:
	mov		[di+DPT.bShLtoP], al
	mov		[di+DPT.wLHeads], dx
	mov		[di+DPT.wLCyls], cx
	clc
	ret


;--------------------------------------------------------------------
; L-CHS geometry for the LBA translation modes. Called only for drives
; that support LBA and have no user specified P-CHS.
;
; CreateDPT_StoreLbaTranslatedLCHSwith255Heads (XLATE_MODE_LBA_255)
;	255 heads, 63 sectors per track, cylinders from the LBA sector
;	count (at most 1024).
; CreateDPT_StoreLbaAssistedLCHS (XLATE_MODE_LBA_ASSIST, over 1024 P-CHS cylinders)
;	63 sectors per track and heads rounded up to 16, 32, 64, 128 or 255,
;	from the P-CHS sector count (same as XTIDE Universal BIOS 2.x):
;	CH = P-CHS sector count / 63
;	Heads = ((CH - 1) / 1024) + 1, rounded up to 16, 32, 64, 128 or 255
;	Cylinders = CH / Heads (at most 1024)
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table (P-CHS stored; for LBA assist
;				heads 1...16 and sectors 1...63, so no division overflows
;				for any cylinder count)
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;	Returns:
;		CF:		Cleared
;	Corrupts registers:
;		AX, BX, CX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StoreLbaTranslatedLCHSwith255Heads:
	mov		ax, [es:si+ATA1.dwLBACnt]
	mov		dx, [es:si+ATA1.dwLBACnt+2]
	mov		cx, 255*63
	cmp		dx, cx						; Quotient would not fit in 16 bits?
	jae		SHORT .MaxCylinders			; (way over 1024 cylinders then)
	div		cx							; AX = Cylinders
	MIN_U	ax, 1024
	xchg	cx, ax
	inc		cx
	loop	.StoreWith255Heads			; Drive at least one cylinder?
	jmp		CreateDPT_StoreLCHS.ShiftPCHStoLCHS		; If not, use default mode
.MaxCylinders:
	mov		cx, 1024
.StoreWith255Heads:
	mov		dx, 255
	jmp		SHORT CreateDPT_StoreLbaTranslatedLCHSfromCXDX

ALIGN JUMP_ALIGN
CreateDPT_StoreLbaAssistedLCHS:
	; Value CH = P-CHS sector count / 63 (max 16383*16*63/63 = 262128)
	eMOVZX	ax, BYTE [di+DPT.bPHeads]
	mul		BYTE [di+DPT.bPSect]		; AX = Heads * Sectors per track
	mul		WORD [di+DPT.wPCyls]		; DX:AX = P-CHS sector count
	mov		cx, 63
	xchg	bx, ax						; BX = Sector count low word
	xchg	ax, dx						; AX = Sector count high word
	cwd									; DX = 0 (AX is at most 00FCh)
	div		cx							; AX = High word / 63, DX = remainder
	xchg	ax, bx						; BX = High word of CH, AX = low word
	div		cx							; BX:AX = Value CH
	push	ax
	push	bx
	; Heads = ((CH - 1) / 1024) + 1
	sub		ax, BYTE 1
	sbb		bx, BYTE 0
	mov		cl, 10
	shr		ax, cl
	ror		bx, cl						; BX bits 1...0 to bits 7...6
	or		ax, bx						; AX = (CH - 1) / 1024 (BX is 0...3)
	inc		ax
	; Round up to 16, 32, 64, 128 or 255
	mov		cx, 16
.RoundUpHeads:
	cmp		ax, cx
	jbe		SHORT .HeadsInCX
	shl		cx, 1
	cmp		cx, 256
	jb		SHORT .RoundUpHeads
	dec		cx							; 255 heads, not 256
.HeadsInCX:
	pop		dx							; DX:AX = Value CH
	pop		ax
	div		cx							; AX = Cylinders (max 1027)
	xchg	dx, cx						; DX = Heads
	MIN_U	ax, 1024
	xchg	cx, ax						; CX = Cylinders
	; Fall to CreateDPT_StoreLbaTranslatedLCHSfromCXDX

CreateDPT_StoreLbaTranslatedLCHSfromCXDX:
	or		BYTE [di+DPT.bFlags], FLG_DPT_LBAXLATE
	mov		BYTE [di+DPT.bLSect], 63
	xor		al, al						; No shifting (LBA addressing)
	jmp		CreateDPT_StoreLCHSfromCXDXwithShiftInAL


;--------------------------------------------------------------------
; Returns L-CHS values from P-CHS values.
; Sectors per track is always the same for both addressing modes.
;
; CreateDPT_ShiftPCHtoLCH:
;	Parameters:
;		CX:		Number of P-CHS cylinders (1...16383)
;		DX:		Number of P-CHS heads (1...16)
;	Returns:
;		AL:		Number of bits shifted
;		CX:		Number of L-CHS cylinders (1...1024)
;		DX:		Number of L-CHS heads (1...256)
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_ShiftPCHtoLCH:
	xor		al, al				; Zero AL
ALIGN JUMP_ALIGN
.ShiftLoop:
	cmp		cx, 1024			; Need to shift?
	jbe		SHORT .Return		;  If not, return
	inc		ax					; Increment shift count
	shr		cx, 1				; Halve cylinders
	shl		dx, 1				; Double heads
	jmp		SHORT .ShiftLoop
ALIGN JUMP_ALIGN
.Return:
	ret


;--------------------------------------------------------------------
; Stores addressing information (L-CHS, P-CHS, LBA28 or LBA48).
;
; CreateDPT_StoreAddressing
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StoreAddressing:
	test	BYTE [di+DPT.bFlags], FLG_DPT_LBAXLATE
	jnz		SHORT .StoreLBA					; L-CHS geometry needs LBA addressing
	cmp		WORD [di+DPT.wPCyls], 1024		; L-CHS possible? (no translation needed)
	jbe		SHORT .Return					;  If so, nothing needs to be changed
	test	BYTE [di+DPT.bFlags], FLG_DPT_USERCHS
	jnz		SHORT .StorePCHS				; Use user defined P-CHS
	test	WORD [es:si+ATA1.wCaps], A2_wCaps_LBA
	jz		SHORT .StorePCHS				; Use P-CHS since LBA not supported
.StoreLBA:
	test	WORD [es:si+ATA6.wSetSup83], A6_wSetSup83_LBA48
	jz		SHORT .StoreLBA28				; Use LBA-28 since LBA-48 not supported
	or		BYTE [di+DPT.bFlags], ADDR_DPT_LBA48<<1
ALIGN JUMP_ALIGN
.StoreLBA28:
	or		BYTE [di+DPT.bFlags], ADDR_DPT_LBA28<<1
	or		BYTE [di+DPT.bDrvSel], FLG_IDE_DRVHD_LBA
	ret
ALIGN JUMP_ALIGN
.StorePCHS:
	or		BYTE [di+DPT.bFlags], ADDR_DPT_PCHS<<1
ALIGN JUMP_ALIGN
.Return:
	clc
	ret


;--------------------------------------------------------------------
; Stores Block Mode information.
;
; CreateDPT_StoreBlockMode
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StoreBlockMode:
	mov		al, 1						; Minimum block size is 1 sector
	mov		ah, [es:si+ATA1.bBlckSize]	; Load max block size in sectors
	mov		[di+DPT.wSetAndMaxBlock], ax
	ret


;--------------------------------------------------------------------
; Stores variables required by EBIOS functions.
;
; CreateDPT_StoreEBIOSSupport
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		AX, BX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StoreEBIOSSupport:
	test	BYTE [cs:ROMVARS.wFlags], FLG_ROMVARS_FULLMODE	; (clears CF)
	jz		SHORT .DoNotSupportEBIOS	; No EBIOS support since small DPTs needed
	mov		bl, [di+DPT.bFlags]
	and		bx, BYTE MASK_DPT_ADDR		; Addressing mode (clears CF)
	jmp		[cs:bx+.rgwAddrJmp]			; Jump to handle addressing mode
ALIGN WORD_ALIGN
.rgwAddrJmp:
	dw		.DoNotSupportEBIOS			; ADDR_DPT_LCHS
	dw		.DoNotSupportEBIOS			; ADDR_DPT_PCHS
	dw		.SupportForLBA28			; ADDR_DPT_LBA28
	dw		.SupportForLBA48			; ADDR_DPT_LBA48
ALIGN JUMP_ALIGN
.DoNotSupportEBIOS:
	ret
ALIGN JUMP_ALIGN
.SupportForLBA28:
	sub		BYTE [di+DPT.bSize], 2		; Only 4 bytes for sector count
ALIGN JUMP_ALIGN
.SupportForLBA48:
	add		BYTE [di+DPT.bSize], EBDPT_size - DPT_size
	or		BYTE [di+DPT.bFlags], FLG_DPT_EBIOS
	; Fall to CreateDPT_StoreEbiosSectorCount

;--------------------------------------------------------------------
; Stores EBIOS total sector count for LBA addressing.
;
; CreateDPT_StoreEbiosSectorCount
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;	Returns:
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		AX, BX, DX
;--------------------------------------------------------------------
;ALIGN JUMP_ALIGN
CreateDPT_StoreEbiosSectorCount:
	call	AtaID_GetTotalSectorCount
	mov		[di+EBDPT.twCapacity], ax
	mov		[di+EBDPT.twCapacity+2], dx
	mov		[di+EBDPT.twCapacity+4], bx
	clc
	ret


;--------------------------------------------------------------------
; Stores number for drive and updates drive count.
;
; CreateDPT_StoreDriveNumberAndUpdateDriveCount
;	Parameters:
;		DS:DI:	Ptr to Disk Parameter Table
;		ES:SI:	Ptr to 512-byte ATA information read from the drive
;		ES:		BDA Segment
;	Returns:
;		DL:		Drive number for new drive
;		CF:		Cleared if DPT parameters stored successfully
;				Set if any error
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CreateDPT_StoreDriveNumberAndUpdateDriveCount:
	; Make sure that more drives can be accepted
	mov		dl, [es:BDA.bHDCount]	; Load number of hard disks
	test	dl, 80h					; Hard disks at maximum?
	stc								; Assume error
	jnz		SHORT .TooManyDrives	;  If so, return

	; Store drive number to DPT
	or		dl, 80h					; Set bit 7 since hard disk
	mov		[di+DPT.bDrvNum], dl	; Store drive number

	; Update BDA and RAMVARS
	inc		BYTE [es:BDA.bHDCount]	; Increment drive count to BDA
	call	RamVars_IncrementHardDiskCount
	clc
.TooManyDrives:
	ret
