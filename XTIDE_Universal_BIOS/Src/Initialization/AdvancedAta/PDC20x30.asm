; Project name	:	XTIDE Universal BIOS
; Description	:	Functions for initializing Promise
;					PDC 20230 and 20630 VLB IDE Controllers.

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
; PDC20x30_DetectControllerForIdeBaseInBX
;	Parameters:
;		BX:		IDE Base Port
;	Returns:
;		AX:		ID WORD for detected controller
;		DX:		Controller base port
;		CF:		Set if PDC detected
;	Corrupts registers:
;		BX (only when PDC detected)
;--------------------------------------------------------------------
PDC20x30_DetectControllerForIdeBaseInBX:
	mov		dx, bx
	call	EnablePdcProgrammingMode
	jnz		SHORT DisablePdcProgrammingMode.Return	; PDC controller not detected
;	ePUSH_T	ax, DisablePdcProgrammingMode			; Uncomment this if GetPdcIDtoAX needs to be a real function
	; Fall to GetPdcIDtoAX

;--------------------------------------------------------------------
; Programming mode must be enabled for this function.
; This function also enables PDC 20630 extra registers.
;
; GetPdcIDtoAX
;	Parameters:
;		DX:		IDE Base port
;	Returns:
;		AH:		PDC ID
;	Corrupts registers:
;		AL, BX
;--------------------------------------------------------------------
GetPdcIDtoAX:
;Force ID_PDC20230 instead of PDC20630 detection
;mov	ax, ID_PDC20230<<8
;jmp		SHORT DisablePdcProgrammingMode

	push	dx

	; Try to enable PDC 20630 extra registers
	add		dx, BYTE LOW_CYLINDER_REGISTER
	in		al, dx
	or		al, FLG_PDCLCR_ENABLE_EXTRA_REGISTERS
	out		dx, al

	; Try to access PDC 20630 registers to see if they are available
	; Hopefully this does not cause problems for systems with PDC 20230
	add		dx, BYTE PDC20630_INDEX_REGISTER - LOW_CYLINDER_REGISTER
	mov		al, PDCREG7_STATUS	; Try to access PDC 20630 status register
	out		dx, al
	xchg	bx, ax
	in		al, dx				; Does index register contain status register index?
	cmp		al, bl
	mov		ah, ID_PDC20630
	eCMOVNE	ah, ID_PDC20230

	pop		dx
;	ret							; Uncomment this to make GetPdcIDtoAX a real function
	; Fall to DisablePdcProgrammingMode


;--------------------------------------------------------------------
; DisablePdcProgrammingMode
;	Parameters:
;		DX:		Base port
;	Returns:
;		CF:		Set
;	Corrupts registers:
;		AL
;--------------------------------------------------------------------
DisablePdcProgrammingMode:
	add		dx, BYTE HIGH_CYLINDER_REGISTER	; 1F5h
	in		al, dx
	add		dx, -HIGH_CYLINDER_REGISTER		; Sets CF for PDC20x30_DetectControllerForIdeBaseInBX
%if 0
	; Disassembly of VG4.BIN shows that bit 7 (programming mode activated)
	; is cleared manually after reading from HIGH_CYLINDER_REGISTER
	; That does not seem to be necessary.
	inc		dx
	inc		dx
	call	AdvAtaInit_InputWithDelay
	and		al, 7Fh
	out		dx, al
	dec		dx
	dec		dx
	stc
%endif
.Return:
	ret


;--------------------------------------------------------------------
; EnablePdcProgrammingMode
;	Parameters:
;		DX:		Base port
;	Returns:
;		CF:		Cleared
;		ZF:		Set if programming mode enabled
;	Corrupts registers:
;		AL
;--------------------------------------------------------------------
EnablePdcProgrammingMode:
	; Set bit 7 to sector count register
	inc		dx
	inc		dx
	call	AdvAtaInit_InputWithDelay	; 1F2h (SECTOR_COUNT_REGISTER)
	or		al, 80h
	out		dx, al

	; PDC detection sequence
	add		dx, BYTE HIGH_CYLINDER_REGISTER - SECTOR_COUNT_REGISTER	; 5 - 2
	cli
	call	AdvAtaInit_InputWithDelay	; 1F5

	sub		dx, BYTE HIGH_CYLINDER_REGISTER - SECTOR_COUNT_REGISTER
	call	AdvAtaInit_InputWithDelay	; 1F2h

	add		dx, STANDARD_CONTROL_BLOCK_OFFSET + (ALTERNATE_STATUS_REGISTER_in - SECTOR_COUNT_REGISTER)	; 200h+(6-2)
	call	AdvAtaInit_InputWithDelay	; 3F6h

	call	AdvAtaInit_InputWithDelay	; 3F6h

	sub		dx, STANDARD_CONTROL_BLOCK_OFFSET + (ALTERNATE_STATUS_REGISTER_in - SECTOR_COUNT_REGISTER)
	call	AdvAtaInit_InputWithDelay	; 1F2h

	call	AdvAtaInit_InputWithDelay	; 1F2h
	sti

	; PDC20230C and PDC20630 clears the bit we set at the beginning
	call	AdvAtaInit_InputWithDelay	; 1F2h
	dec		dx
	dec		dx		; Base port
	test	al, 80h	; Clears CF
	ret


;--------------------------------------------------------------------
; PDC20x30_GetMaxPioModeToALandMinPioCycleTimeToBX
;	Parameters:
;		AX:		ID WORD specific for detected controller
;	Returns:
;		AL:		Max supported PIO mode (only if ZF set)
;		AH:		~FLGH_DPT_IORDY if IORDY not supported, -1 otherwise (only if ZF set)
;		BX:		Min PIO cycle time (only if ZF set)
;		ZF:		Set if PIO limit necessary
;				Cleared if no need to limit timings
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
PDC20x30_GetMaxPioModeToALandMinPioCycleTimeToBX:
	cmp		ah, ID_PDC20230
	jne		SHORT .Return							; No need to limit anything for ID_PDC20630
	mov		ax, (~FLGH_DPT_IORDY & 0FFh) << 8 | 2	; Limit PIO to 2 for ID_PDC20230
	mov		bx, PIO_2_MIN_CYCLE_TIME_NS
.Return:
	ret


;--------------------------------------------------------------------
; PDC20x30_InitializeForDPTinDSDI
;	Parameters:
;		DS:DI:	Ptr to DPT for Single or Slave Drive
;	Returns:
;		AH:		Int 13h return status
;		CF:		Cleared if success or no controller to initialize
;				Set if error
;	Corrupts registers:
;		AL, BX, CX, DX
;--------------------------------------------------------------------
PDC20x30_InitializeForDPTinDSDI:
%ifdef USE_386
	xor		ch, ch
	test	BYTE [di+DPT.bFlagsLow], FLGL_DPT_SLAVE
	setnz	cl
%else
	xor		cx, cx
	test	BYTE [di+DPT.bFlagsLow], FLGL_DPT_SLAVE
	jz		SHORT .NotSlave
	inc		cx
.NotSlave:
%endif

	mov		dx, [di+DPT.wBasePort]
	call	EnablePdcProgrammingMode
	call	SetSpeedForDriveInCX
	cmp		BYTE [di+DPT_ADVANCED_ATA.wControllerID+1], ID_PDC20630
	jne		SHORT .InitializationCompleted
	call	SetPdc20630SpeedForDriveInCX

	; TODO: Should we first call SetPdc20630SpeedForDriveInCX and then
	; force SetSpeedForDriveInCX to PIO 0 (maximum speed setting 8)?
	; Need to test with PCD20630.

.InitializationCompleted:
	mov		dx, [di+DPT.wBasePort]
	call	DisablePdcProgrammingMode
	xor		ah, ah
	ret


;--------------------------------------------------------------------
; SetSpeedForDriveInCX
;	Parameters:
;		CX:		0 for master, 1 for slave drive
;		DX:		IDE Base port
;		DS:DI:	Ptr to DPT
;	Returns:
;		DX:		Sector Number Register (1F3h)
;	Corrupts registers:
;		AX, BX
;--------------------------------------------------------------------
SetSpeedForDriveInCX:
	mov		bx, .rgbPioModeToPDCspeedValue
	mov		al, [di+DPT_ADVANCED_ATA.bPioMode]
	MIN_U	al, 2	; Limit to PIO2
	cs xlat
	xchg	bx, ax

	add		dx, BYTE SECTOR_NUMBER_REGISTER	; 1F3h
	mov		bh, ~MASK_PDCSNR_DEV1SPEED		; Assume slave
	inc		cx
	mov		ah, 7	; Max speed value. Set unknown bit 7 if either of drives are set to this
	loop	.SetSpeed
	mov		ah, 7 << POS_PDCSNR_DEV0SPEED
	eSHL_IM	bl, POS_PDCSNR_DEV0SPEED
	mov		bh, ~MASK_PDCSNR_DEV0SPEED
.SetSpeed:
	in		al, dx
	and		al, bh
	or		al, bl
	cmp		bl, ah
	jb		SHORT .OutputNewValue
	or		al, FLG_PDCSNR_UNKNOWN_BIT7		; Flag for PIO 2 and above?
.OutputNewValue:
	out		dx, al

	; The above speed set does not work with Octek VL-COMBO rev 3.2 with PDC20230C
	; Only thing to make it work is to set FLG_PDCSCR_BOTHMAX to 1F2h. Are all PDC20230C controllers
	; like that? If so, why the above speed is not set? Or does the VL-COMBO or other PDC20230C
	; controllers have a jumper to prevent speed setup by software? (PDC20230B can only be set
	; by hardware, for example), like pin-compatible operation with older PDC20230B, perhaps?
	; Datasheets would be very useful...
	; For now, we just set the FLG_PDCSCR_BOTHMAX bit if either of the drives are set to speed 7
	;
	; Code below is not perfect. It does not properly test if both drives support PIO 2 but
	; likely if slave does, so does master (and if slave does not, we clear the
	; FLG_PDCSCR_BOTHMAX set by master)
	mov		bl, 1	; Set bit 0, see VG4.BIN comments below
	test	al, al
	jns		SHORT .DoNotSetMaxSpeedBit
	or		bl, FLG_PDCSCR_BOTHMAX
.DoNotSetMaxSpeedBit:
	dec		dx		; SECTOR_COUNT_REGISTER, 1F2h
	call	AdvAtaInit_InputWithDelay
	and		al, ~FLG_PDCSCR_BOTHMAX
	or		al, bl
	out		dx, al

	; VG4.BIN ("External BIOS") does the following after programming speed (1F3h)
	; (It never seems to set the speed bit we just set above).
	; The below code does not seem to have any effect, at least not for PDC20230C.
	; Why is bit 0 set to 1F2h?
	; Is it just to keep programming mode active if it has timeout, for example?
	; But after all that it just reads 1F5h to disable programming mode.
%if 0
	; Test code start
	push	cx
	mov		cx, 100
	DELAY_WITH_LOOP_INSTRUCTION_NA

	; Does below tell the controller that new speed is set?
	in		al, dx
	or		al, 1
	out		dx, al

	mov		cl, 100
	DELAY_WITH_LOOP_INSTRUCTION_NA
	pop		cx
	; Test code end
%endif

	inc		dx		; SECTOR_NUMBER_REGISTER, 1F3h
	ret

.rgbPioModeToPDCspeedValue:
	db		0		; PIO 0
	db		4		; PIO 1
	db		7		; PIO 2


;--------------------------------------------------------------------
; SetPdc20630SpeedForDriveInCX
;	Parameters:
;		CX:		0 for master, 1 for slave drive
;		DS:DI:	Ptr to DPT
;		DX:		Sector Number Register, 1F3h
;	Returns:
;		DX:		Low Cylinder Register
;	Corrupts registers:
;		AX
;--------------------------------------------------------------------
SetPdc20630SpeedForDriveInCX:
	inc		dx		; LOW_CYLINDER_REGISTER
	mov		ah, ~(FLG_PDCLCR_DEV0SPEED_BIT4 | FLG_PDCLCR_DEV0IORDY)
	ror		ah, cl
	in		al, dx
	and		al, ah	; Clear drive specific bits
	cmp		BYTE [di+DPT_ADVANCED_ATA.bPioMode], 2
	jbe		.ClearBitsOnly
	not		ah
	or		al, ah
.ClearBitsOnly:
	out		dx, al
	ret

