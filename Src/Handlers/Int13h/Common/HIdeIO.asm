; File name		:	HIdeIO.asm
; Project name	:	Rivet
; Created date	:	4.11.2026
; Author		:	Glitch Works, LLC
; Description	:	IDE register port access with support for XT-IDE
;					HI-SPEED mode (A0 and A3 swapped, "Chuck mod").
;
; Rivet Option ROM
; Copyright (C) 2026 Glitch Works, LLC
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License version 2 as
; published by the Free Software Foundation.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
; GNU General Public License for more details.

; Section containing code
SECTION .text

;--------------------------------------------------------------------
; Outputs a byte to, or inputs a byte from, an IDE register.
;
; Callers keep computing register addresses for the standard IDE
; layout (base + register offset). On XT-IDE boards jumpered for
; HI-SPEED mode, ISA A0 and A3 are swapped, so for the controller
; currently being accessed the port address is translated here, for
; this one access only. DX is returned unchanged, so callers can keep
; stepping DX from register to register as before.
;
; Translation swaps bits 0 and 3 of DX. This needs the controller's
; 16-port window (Command Block at base, Control Block at base+8) to
; start at a 16-byte aligned address, which XT-IDE always does.
;
; HIdeIO_OutputALtoPortDX
; HIdeIO_InputALfromPortDX
;	Parameters:
;		AL:		Byte to output (output only)
;		DX:		IDE register address in standard layout
;		DS:		RAMVARS segment
;	Returns:
;		AL:		Byte read (input only)
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
HIdeIO_OutputALtoPortDX:
	push	dx
	call	HIdeIO_TranslatePortInDX
	out		dx, al
	pop		dx
	ret

ALIGN JUMP_ALIGN
HIdeIO_InputALfromPortDX:
	push	dx
	call	HIdeIO_TranslatePortInDX
	in		al, dx
	pop		dx
	ret


;--------------------------------------------------------------------
; Swaps A0 and A3 of DX if the current controller is in HI-SPEED mode.
;
; HIdeIO_TranslatePortInDX
;	Parameters:
;		DX:		IDE register address in standard layout
;		DS:		RAMVARS segment
;	Returns:
;		DX:		Physical port address for the current controller
;	Corrupts registers:
;		FLAGS
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
HIdeIO_TranslatePortInDX:
	cmp		BYTE [RAMVARS.bIdeBusType], BUS_TYPE_8_HISPEED
	jne		SHORT .Return
	test	dl, 1001b				; Look at A3 and A0 only
	jpe		SHORT .Return			; Both or neither set: swap changes nothing
	xor		dl, 1001b				; Exactly one set: swap them
.Return:
	ret
