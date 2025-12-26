; Project name	:	XTIDE Universal BIOS
; Description	:	IDE Read/Write functions for transferring block using PIO modes.
;					These functions should only be called from IdeTransfer.asm.

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


; --------------------------------------------------------------------------------------------------
;
; READ routines follow
;
; --------------------------------------------------------------------------------------------------

%ifdef MODULE_8BIT_IDE
;--------------------------------------------------------------------
; IdePioBlock_ReadFromXtideRev1
;	Parameters:
;		CX:		Block size in 512 byte sectors
;		DX:		IDE Data port address
;		ES:DI:	Normalized ptr to buffer to receive data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_ReadFromXtideRev1:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_32WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%else
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%endif
	mov		bl, 8		; Bit mask for toggling data low/high reg
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 32	; WORDs
		XTIDE_INSW
	%endrep
	dec		cx
%ifdef USE_386
	jnz		.NextIteration
%else
	jz		SHORT .BlockTransferred
	jmp		.NextIteration

ALIGN JUMP_ALIGN
.BlockTransferred:
%endif
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 16	; WORDs
		XTIDE_INSW
	%endrep
%ifdef USE_186
	loop	.NextIteration
%else
	dec		cx
	jz		SHORT .BlockTransferred
	jmp		.NextIteration

ALIGN JUMP_ALIGN
.BlockTransferred:
%endif
%else
	%rep 8	; WORDs
		XTIDE_INSW
	%endrep
	loop	.NextIteration
%endif
	ret


;--------------------------------------------------------------------
; IdePioBlock_ReadFromXtideRev2_Olivetti
;	Parameters:
;		CX:		Block size in 512 byte sectors
;		DX:		IDE Data port address
;		ES:DI:	Normalized ptr to buffer to receive data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_ReadFromXtideRev2_Olivetti:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_32WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%else
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%endif
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 32	; WORDs
		XTIDE_MOD_OLIVETTI_INSW
	%endrep
	dec		cx
%ifdef USE_386
	jnz		.NextIteration
%else
	jz		SHORT .BlockTransferred
	jmp		.NextIteration

ALIGN JUMP_ALIGN
.BlockTransferred:
%endif
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 16	; WORDs
		XTIDE_MOD_OLIVETTI_INSW
	%endrep
	loop	.NextIteration
%else
	%rep 8	; WORDs
		XTIDE_MOD_OLIVETTI_INSW
	%endrep
	loop	.NextIteration
%endif
	ret


;--------------------------------------------------------------------
; 8-bit PIO from a single data port.
;
; IdePioBlock_ReadFrom8bitDataPort
;	Parameters:
;		CX:		Block size in 512 byte sectors
;		DX:		IDE Data port address
;		ES:DI:	Normalized ptr to buffer to receive data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_ReadFrom8bitDataPort:
%ifdef USE_186
	shl		cx, 9		; Sectors to BYTEs
	rep insb
	ret

%else ; 808x
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_32WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%else
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%endif
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 64	; BYTEs
		in		al, dx	; Read BYTE
		stosb			; Store BYTE to [ES:DI]
	%endrep
	dec		cx
	jz		SHORT .BlockTransferred
	jmp		.NextIteration

ALIGN JUMP_ALIGN
.BlockTransferred:
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 32	; BYTEs
		in		al, dx	; Read BYTE
		stosb			; Store BYTE to [ES:DI]
	%endrep
	loop	.NextIteration
%else
	%rep 16	; BYTEs
		in		al, dx	; Read BYTE
		stosb			; Store BYTE to [ES:DI]
	%endrep
	loop	.NextIteration
%endif
	ret
%endif
%endif ; MODULE_8BIT_IDE


;--------------------------------------------------------------------
; 16-bit and 32-bit PIO from a single data port.
;
; IdePioBlock_ReadFrom16bitDataPort
; IdePioBlock_ReadFrom32bitDataPort
;	Parameters:
;		CX:		Block size in 512 byte sectors
;		DX:		IDE Data port address
;		ES:DI:	Normalized ptr to buffer to receive data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_ReadFrom16bitDataPort:
%ifdef USE_186
	xchg	cl, ch		; Sectors to WORDs
	rep insw
	ret

%else ; 808x
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_32WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%else
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%endif
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 32	; WORDs
		in		ax, dx	; Read WORD
		stosw			; Store WORD to [ES:DI]
	%endrep
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 16	; WORDs
		in		ax, dx	; Read WORD
		stosw			; Store WORD to [ES:DI]
	%endrep
%else
	%rep 8	; WORDs
		in		ax, dx	; Read WORD
		stosw			; Store WORD to [ES:DI]
	%endrep
%endif
	loop	.NextIteration
	ret
%endif


;--------------------------------------------------------------------
%ifdef MODULE_ADVANCED_ATA
ALIGN JUMP_ALIGN
IdePioBlock_ReadFrom32bitDataPort:
	shl		cx, 7		; Sectors to DWORDs
	rep insd
	ret
%endif ; MODULE_ADVANCED_ATA


; --------------------------------------------------------------------------------------------------
;
; WRITE routines follow
;
; --------------------------------------------------------------------------------------------------

%ifdef MODULE_8BIT_IDE
;--------------------------------------------------------------------
; IdePioBlock_WriteToXtideRev1
;	Parameters:
;		CX:		Block size in 512-byte sectors
;		DX:		IDE Data port address
;		DS:SI:	Normalized ptr to buffer containing data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_WriteToXtideRev1:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%else
	UNROLL_SECTORS_IN_CX_TO_QWORDS
%endif
	mov		bl, 8		; Bit mask for toggling data low/high reg
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 16	; WORDs
		XTIDE_OUTSW
	%endrep
%ifdef USE_186
	loop	.NextIteration
%else
	dec		cx
	jz		SHORT .BlockTransferred
	jmp		.NextIteration

ALIGN JUMP_ALIGN
.BlockTransferred:
%endif
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 8	; WORDs
		XTIDE_OUTSW
	%endrep
	loop	.NextIteration
%else
	%rep 4	; WORDs
		XTIDE_OUTSW
	%endrep
	loop	.NextIteration
%endif
	ret


;--------------------------------------------------------------------
; IdePioBlock_WriteToXtideRev2	or rev 1 with swapped A0 and A3 (chuck-mod)
;	Parameters:
;		CX:		Block size in 512-byte sectors
;		DX:		IDE Data port address
;		DS:SI:	Normalized ptr to buffer containing data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_WriteToXtideRev2:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%else
	UNROLL_SECTORS_IN_CX_TO_QWORDS
%endif
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 16	; WORDs
		XTIDE_MOD_OUTSW
	%endrep
%ifdef USE_186
	loop	.NextIteration
%else
	dec		cx
	jz		SHORT .BlockTransferred
	jmp		.NextIteration

ALIGN JUMP_ALIGN
.BlockTransferred:
%endif
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 8	; WORDs
		XTIDE_MOD_OUTSW
	%endrep
	loop	.NextIteration
%else
	%rep 4	; WORDs
		XTIDE_MOD_OUTSW
	%endrep
	loop	.NextIteration
%endif
	ret


;--------------------------------------------------------------------
; IdePioBlock_WriteTo8bitDataPort
;	Parameters:
;		CX:		Block size in 512-byte sectors
;		DX:		IDE Data port address
;		DS:SI:	Normalized ptr to buffer containing data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_WriteTo8bitDataPort:
%ifdef USE_186
	shl		cx, 9		; Sectors to BYTEs
	rep outsb
	ret

%else ; 808x
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%else
	UNROLL_SECTORS_IN_CX_TO_QWORDS
%endif
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 32	; BYTEs
		lodsb			; Load BYTE from [DS:SI]
		out		dx, al	; Write BYTE
	%endrep
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 16	; BYTEs
		lodsb			; Load BYTE from [DS:SI]
		out		dx, al	; Write BYTE
	%endrep
%else
	%rep 8	; BYTEs
		lodsb			; Load BYTE from [DS:SI]
		out		dx, al	; Write BYTE
	%endrep
%endif
	loop	.NextIteration
	ret
%endif


;--------------------------------------------------------------------
; IdePioBlock_WriteToJukoD16X			Juko Laboratories, Ltd. D16-X
;	Parameters:
;		CX:		Block size in 512-byte sectors
;		DX:		IDE Data port address
;		DS:SI:	Normalized ptr to buffer containing data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_WriteToJukoD16X:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%else
	UNROLL_SECTORS_IN_CX_TO_QWORDS
%endif
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 16	; WORDs
		lodsw			; Load WORD from [DS:SI]
		xchg	ah, al
		out		dx, ax	; Write WORD
	%endrep
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 8	; WORDs
		lodsw			; Load WORD from [DS:SI]
		xchg	ah, al
		out		dx, ax	; Write WORD
	%endrep
%else
	%rep 4	; WORDs
		lodsw			; Load WORD from [DS:SI]
		xchg	ah, al
		out		dx, ax	; Write WORD
	%endrep
%endif
	loop	.NextIteration
	ret
%endif ; MODULE_8BIT_IDE


;--------------------------------------------------------------------
; IdePioBlock_WriteTo16bitDataPort		Normal 16-bit IDE, XT-CFv3 in BIU Mode
; IdePioBlock_WriteTo32bitDataPort		VLB/PCI 32-bit IDE
;	Parameters:
;		CX:		Block size in 512-byte sectors
;		DX:		IDE Data port address
;		DS:SI:	Normalized ptr to buffer containing data
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
IdePioBlock_WriteTo16bitDataPort:
%ifdef USE_186
	xchg	cl, ch		; Sectors to WORDs
	rep outsw
	ret

%else ; 808x
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	UNROLL_SECTORS_IN_CX_TO_16WORDS
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	UNROLL_SECTORS_IN_CX_TO_OWORDS
%else
	UNROLL_SECTORS_IN_CX_TO_QWORDS
%endif
ALIGN JUMP_ALIGN
.NextIteration:
%ifdef EXTRA_LOOP_UNROLLING_LARGE
	%rep 16	; WORDs
		lodsw			; Load WORD from [DS:SI]
		out		dx, ax	; Write WORD
	%endrep
%elifdef EXTRA_LOOP_UNROLLING_SMALL
	%rep 8	; WORDs
		lodsw			; Load WORD from [DS:SI]
		out		dx, ax	; Write WORD
	%endrep
%else
	%rep 4	; WORDs
		lodsw			; Load WORD from [DS:SI]
		out		dx, ax	; Write WORD
	%endrep
%endif
	loop	.NextIteration
	ret
%endif

;--------------------------------------------------------------------
%ifdef MODULE_ADVANCED_ATA
ALIGN JUMP_ALIGN
IdePioBlock_WriteTo32bitDataPort:
	shl		cx, 7		; Sectors to DWORDs
	rep outsd
	ret
%endif ; MODULE_ADVANCED_ATA
