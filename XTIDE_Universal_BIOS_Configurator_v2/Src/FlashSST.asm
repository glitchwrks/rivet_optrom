; Project name	:	XTIDE Universal BIOS Configurator v2
; Description	:	Functions for flashing SST flash devices.

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
; FlashSst_WithFlashvarsInDSBX
;	Parameters:
;		DS:BX:	Ptr to FLASHVARS
;	Returns:
;		Updated FLASHVARS in DS:BX
;	Corrupts registers:
;		AX, DX, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
FlashSst_WithFlashvarsInDSBX:
	push	ds
	push	es
	push	bx
	push	cx
	push	si
	push	bp
	mov		bp, bx					; Flashvars now in SS:BP (Assumes SS=DS)

	mov		BYTE [bp+FLASHVARS.bFlashResult], FLASH_RESULT.DeviceNotDetected
	call	DetectSstDevice
	jc		SHORT .ExitOnError

	call	CalibrateSstTimeout

	mov		BYTE [bp+FLASHVARS.bFlashResult], FLASH_RESULT.PollingTimeoutError
	mov		cx, [bp+FLASHVARS.wPagesToFlash]
	mov		dx, [bp+FLASHVARS.wEepromPageSize]
	les		di, [bp+FLASHVARS.fpNextSourcePage]
	lds		si, [bp+FLASHVARS.fpNextDestinationPage]
%ifdef CLD_NEEDED
	cld
%endif

ALIGN JUMP_ALIGN
.NextPage:
	; See if this page needs updating.
	push	si
	push	di
	push	cx
	mov		cx, dx
	repe cmpsb
	pop		cx
	pop		di
	pop		si
	jne		SHORT .FlashThisPage
	add		si, dx
	add		di, dx
	jmp		SHORT .ContinueLoop

.FlashThisPage:
	call	EraseSstPage
	jc		SHORT .ExitOnError
	call	WriteSstPage
	jc		SHORT .ExitOnError
.ContinueLoop:
	loop	.NextPage

	; The write process has already confirmed the results one byte at a time.
	; Here we do an additional verify check just in case there was some
	; kind of oddity with pages / addresses.
	mov		BYTE [bp+FLASHVARS.bFlashResult], FLASH_RESULT.DataVerifyError
%ifndef USE_186
	mov		ax, [bp+FLASHVARS.wPagesToFlash]
	mov		cl, SST_PAGE_SIZE_SHIFT - 1		; -1 because we compare WORDs (verifying 64 KB won't work otherwise)
	shl		ax, cl
	xchg	cx, ax
%else
	mov		cx, [bp+FLASHVARS.wPagesToFlash]
	shl		cx, SST_PAGE_SIZE_SHIFT - 1
%endif
	lds		si, [bp+FLASHVARS.fpNextSourcePage]
	les		di, [bp+FLASHVARS.fpNextDestinationPage]
	repe cmpsw
	jne		SHORT .ExitOnError

%ifndef CHECK_FOR_UNUSED_ENTRYPOINTS
%if FLASH_RESULT.Success = 0	; Just in case this should ever change
	mov		[bp+FLASHVARS.bFlashResult], cl
%else
	mov		BYTE [bp+FLASHVARS.bFlashResult], FLASH_RESULT.Success
%endif
%endif
ALIGN JUMP_ALIGN
.ExitOnError:
	pop		bp
	pop		si
	pop		cx
	pop		bx
	pop		es
	pop		ds
	ret

;--------------------------------------------------------------------
; DetectSstDevice
;	Parameters:
;		SS:BP:	Ptr to FLASHVARS
;	Returns:
;		CF:	Clear if supported SST device found
;			Set if supported SST device not found
;	Corrupts registers:
;		AX, BX, SI, DS
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
DetectSstDevice:
	lds		si, [bp+FLASHVARS.fpNextDestinationPage]
	mov		bx, 5555h

	cli
	mov		BYTE [bx], 0AAh			; Enter software ID sequence.
	shr		bx, 1					; BX=2AAAh, CF=1
	mov		BYTE [bx], 55h
	eRCL_IM	bx, 1					; BX=5555h
	mov		BYTE [bx], 90h
	mov		al, [si]				; Extra reads to be sure device
	mov		al, [si]				; has time to respond.
	mov		al, [si]
	mov		ah, [si]				; Vendor ID in AH.
	mov		al, [si+1]				; Device ID in AL.
	mov		BYTE [bx], 0F0h			; Exit software ID.
	sti

	cmp		ax, 0BFB4h
	jb		SHORT .NotValidDevice
	cmp		ax, 0BFB7h+1
	cmc
.NotValidDevice:
	ret

;--------------------------------------------------------------------
; CalibrateSstTimeout
;	Parameters:
;		SS:BP:	Ptr to FLASHVARS
;	Returns:
;		FLASHVARS.wTimeoutCounter
;	Corrupts registers:
;		AX, BX, CX, SI, DI, DS, ES
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
CalibrateSstTimeout:
	LOAD_BDA_SEGMENT_TO	es, cx, !
	mov		ds, [bp+FLASHVARS.fpNextDestinationPage+2]
	mov		bx, BDA.dwTimerTicks
	mov		si, cx
	mov		di, cx
	mov		al, [di]
	inc		ax						; Forces poll to fail

	mov		ah, [es:bx]				; Read low byte only
	inc		ah
.WaitForFirstIncrement:
	cmp		ah, [es:bx]
	jne		SHORT .WaitForFirstIncrement

	inc		ah

.WaitForSecondIncrement:
	inc		ch						; CX now 0x0100
.PollLoop:							; Identical to poll loop used
	cmp		[di], al				; during programming
	loopne	.PollLoop				; Will never be equal in this case
	inc		si						; Number of poll loops completed
	jz		SHORT .CountOverflow
	cmp		ah, [es:bx]
	jne		SHORT .WaitForSecondIncrement
	SKIP1B	al
.CountOverflow:
	; Clamp on overflow, although it should not be possible on
	; real hardware. In principle SI could overflow on a very
	; fast CPU. However the SST device is on a slow bus. Even
	; running at the min read cycle time of fastest version of
	; the device, SI can not overflow.
	dec		si

	; SI ~= number of polling loops in 215us.
	mov		[bp+FLASHVARS.wTimeoutCounter], si
	ret

;--------------------------------------------------------------------
; EraseSstPage
;	Parameters:
;		DS:SI:	Destination ptr
;	Returns:
;		CF:		Set on error.
;	Corrupts registers:
;		AX, BX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
EraseSstPage:
	push	cx

	mov		bx, 5555h
	mov		ax, 2AAAh

	; Sector erase sequence.
	mov		[bx], al				; [5555h] <- AAh
	xchg	bx, ax
	mov		[bx], al				; [2AAAh] <- 55h
	xchg	bx, ax
	mov		BYTE [bx], 80h			; [5555h] <- 80h
	mov		[bx], al				; [5555h] <- AAh
	xchg	bx, ax
	mov		[bx], al				; [2AAAh] <- 55h
	mov		BYTE [si], 30h

	or		bl, al					; BL = 0FFh
	mov		ax, 1163				; 1163 x ~215us = 250ms = 10x datasheet max
.TimeoutOuterLoop:
	mov		cx, [bp+FLASHVARS.wTimeoutCounter]
.TimeoutInnerLoop:
	cmp		[si], bl				; Will return 0FFh when erase complete
	loopne	.TimeoutInnerLoop
	je		SHORT .Return
	dec		ax
	jnz		SHORT .TimeoutOuterLoop
	; Timed out (CF=1)
.Return:
	pop		cx
	ret

;--------------------------------------------------------------------
; WriteSstPage
;	Parameters:
;		DX:		EEPROM page size
;		DS:SI:	Destination ptr
;		ES:DI:	Source ptr
;	Returns:
;		SI, DI:	Each advanced forward 1 page.
;		CF:		Set on error.
;	Corrupts registers:
;		AL, BX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
WriteSstPage:
	push	cx
	push	dx

	mov		bx, [bp+FLASHVARS.wTimeoutCounter]
	xchg	si, di
	cli

.NextByte:
	es lodsb						; Read byte from ES:SI
	mov		BYTE [5555h], 0AAh		; Byte program sequence.
	mov		BYTE [2AAAh], 55h
	mov		BYTE [5555h], 0A0h
	mov		[di], al				; Write byte to DS:DI

	mov		cx, bx
.WaitLoop:
	cmp		[di], al				; Device won't return actual data until write complete.
	loopne	.WaitLoop				; Timeout ~215us, or ~10x 20us max program time from datasheet.
	jne		SHORT .WriteTimeout

	inc		di
	dec		dx
	jnz		SHORT .NextByte
	SKIP1B	al
.WriteTimeout:
	stc
	sti
	xchg	si, di
	pop		dx
	pop		cx
	ret
