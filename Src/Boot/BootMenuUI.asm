; File name		:	BootMenuUI.asm
; Project name	:	Rivet
; Created date	:	4.11.2026
; Author		:	Glitch Works, LLC
; Description	:	Boot Menu drawing and keyboard handling.
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
;
; A purpose-built replacement for the generic menu library. It draws the
; same menu, but only redraws what changes:
;	- The frame, title and all lines are drawn once when the menu opens.
;	- Moving the selection redraws the two selection arrows, the drive
;	  number fields (drive translation changes them) and the info box.
;	  Scrolling redraws the visible menuitems.
;	- The timeout redraws only its digits, and only when the displayed
;	  number of seconds changes.
; All drawing goes through the BIOS: INT 10h AH=02h (set cursor) and
; AH=0Eh (teletype), so it works with serial console redirection.

; Section containing code
SECTION .text

; Variables for the menu, stored to stack (SS:BP)
struc BMVARS
	.wItemCnt		resb	2	; Number of menuitems
	.wItemSel		resb	2	; Index of selected menuitem (-1 when cancelled)
	.wItemTop		resb	2	; Index of topmost visible menuitem
	.wTimeInit		resb	2	; Timeout in timer ticks (0 = disabled)
	.wTimeLeft		resb	2	; Timer ticks left before timeout
	.wTimeLast		resb	2	; Timer tick count when last checked
	.wSecs			resb	2	; Seconds currently displayed
	.bLeft			resb	1	; X coordinate of left border
	.bTop			resb	1	; Y coordinate of top border
	.bVisCnt		resb	1	; Number of visible menuitems
	.bRow			resb	1	; Row being drawn by BootMenuUI_EndContentLine
endstruc

; Menu geometry
BMUI_WIDTH			EQU		MENU_WIDTH_IN_CHARS		; Including borders
BMUI_CONTENT_X		EQU		2						; Content start from left border
BMUI_CONTENT_W		EQU		BMUI_WIDTH - 4			; Content width
BMUI_DRVNUM_X		EQU		4						; Drive number from left border
BMUI_SCREEN_ROWS	EQU		25
BMUI_TIMEOUT_X		EQU		20						; Timeout digits from left border

; Keyboard scan codes
BMUI_KEY_ENTER		EQU		1Ch
BMUI_KEY_ESC		EQU		01h
BMUI_KEY_UP			EQU		48h
BMUI_KEY_DOWN		EQU		50h
BMUI_KEY_PGUP		EQU		49h
BMUI_KEY_PGDN		EQU		51h
BMUI_KEY_HOME		EQU		47h
BMUI_KEY_END		EQU		4Fh


;--------------------------------------------------------------------
; Displays the menu until a menuitem is selected or ESC is pressed.
;
; BootMenuUI_Run
;	Parameters:
;		CX:		Number of menuitems
;		DS:		RAMVARS segment
;	Returns:
;		CX:		Index of selected menuitem
;				FFFFh if cancelled with ESC
;	Corrupts registers:
;		AX, BX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_Run:
	push	bp
	sub		sp, BYTE BMVARS_size
	mov		bp, sp
	mov		[bp+BMVARS.wItemCnt], cx

	; Timeout in timer ticks: seconds * 1000 / 55
	eMOVZX	ax, BYTE [cs:ROMVARS.bBootDelay]
	mov		bx, 1000
	mul		bx
	mov		bx, 55
	div		bx
	mov		[bp+BMVARS.wTimeInit], ax
	mov		[bp+BMVARS.wTimeLeft], ax
	mov		WORD [bp+BMVARS.wSecs], -1

	; Visible menuitems: limit total height to ROMVARS.bBootMnuH
	call	BootMenuUI_GetExtraRowsToAX		; Rows besides menuitems
	mov		bx, cx
	add		bx, ax							; BX = Total height wanted
	eMOVZX	dx, BYTE [cs:ROMVARS.bBootMnuH]
	cmp		bx, dx
	jbe		SHORT .HeightOk
	mov		bx, dx
.HeightOk:
	sub		bx, ax							; BX = Visible menuitems
	jg		SHORT .VisibleOk
	mov		bx, 1
.VisibleOk:
	mov		[bp+BMVARS.bVisCnt], bl
	add		ax, bx							; AX = Total height

	; Center the menu
	mov		dh, BMUI_SCREEN_ROWS
	sub		dh, al
	shr		dh, 1
	mov		[bp+BMVARS.bTop], dh
	push	bp
	mov		ah, 0Fh							; Get Current Video Mode
	int		10h
	pop		bp
	mov		al, ah							; Column count to AL
	sub		al, BMUI_WIDTH
	shr		al, 1
	mov		[bp+BMVARS.bLeft], al

	; Default menuitem
	xor		ax, ax
	mov		[bp+BMVARS.wItemSel], ax
	mov		[bp+BMVARS.wItemTop], ax
	mov		dl, [cs:ROMVARS.bBootDrv]
	call	BootMenu_IsDriveInSystem
	jnc		SHORT .NoDefaultMenuitem
	call	DriveXlate_SetDriveToSwap
	call	BootMenu_ConvertDriveToMenuitem
	mov		[bp+BMVARS.wItemSel], cx
	eMOVZX	ax, BYTE [bp+BMVARS.bVisCnt]
	cmp		cx, ax							; Default visible?
	jb		SHORT .NoDefaultMenuitem
	mov		[bp+BMVARS.wItemTop], cx		; Set default to topmost
.NoDefaultMenuitem:

	; Draw menu and process keys until done
	mov		cx, 2000h						; Hide cursor
	call	BootMenuUI_SetCursorShapeToCX
	call	BootMenuUI_DrawMenu
	call	BootMenuUI_Loop
	mov		cx, 0607h						; Show cursor
	call	BootMenuUI_SetCursorShapeToCX

	mov		cx, [bp+BMVARS.wItemSel]
	add		sp, BYTE BMVARS_size
	pop		bp
	ret


;--------------------------------------------------------------------
; Returns number of menu rows besides menuitems.
;
; BootMenuUI_GetExtraRowsToAX
;	Parameters:
;		Nothing
;	Returns:
;		AX:		Rows needed for borders, title and info
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_GetExtraRowsToAX:
	mov		ax, MENU_HEIGHT_IN_CHARS_WITHOUT_INFO
	test	BYTE [cs:ROMVARS.wFlags], FLG_ROMVARS_DRVNFO
	jz		SHORT .Return
	mov		al, MENU_HEIGHT_IN_CHARS_WITH_INFO
.Return:
	ret


;--------------------------------------------------------------------
; Keyboard and timeout loop.
;
; BootMenuUI_Loop
;	Parameters:
;		DS:		RAMVARS segment
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		BMVARS.wItemSel set
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_Loop:
	call	BootMenuUI_ReadTimeToDX
	mov		[bp+BMVARS.wTimeLast], dx
.CheckKey:
	push	bp
	mov		ah, 01h							; Check for keystroke
	int		16h
	pop		bp
	jz		SHORT .CheckTimeout
	push	bp
	xor		ah, ah							; Read keystroke
	int		16h
	pop		bp
	call	BootMenuUI_ProcessKey
	jc		SHORT .Return					; Menu done

.CheckTimeout:
	cmp		WORD [bp+BMVARS.wTimeInit], BYTE 0
	je		SHORT .CheckKey					; Timeout disabled
	call	BootMenuUI_ReadTimeToDX
	mov		ax, dx
	sub		dx, [bp+BMVARS.wTimeLast]		; Ticks since last check
	jz		SHORT .CheckKey
	mov		[bp+BMVARS.wTimeLast], ax
	sub		[bp+BMVARS.wTimeLeft], dx
	jbe		SHORT .Return					; Timeout: select current
	call	BootMenuUI_DrawTimeoutDigits
	jmp		SHORT .CheckKey
.Return:
	ret


;--------------------------------------------------------------------
; BootMenuUI_ReadTimeToDX
;	Parameters:
;		Nothing
;	Returns:
;		DX:		System timer ticks (low word)
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_ReadTimeToDX:
	push	bp
	xor		ah, ah							; Get System Time
	int		1Ah
	pop		bp
	ret


;--------------------------------------------------------------------
; Processes a keystroke.
;
; BootMenuUI_ProcessKey
;	Parameters:
;		AH:		BIOS scan code
;		AL:		ASCII character
;		DS:		RAMVARS segment
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		CF:		Set if menu is done (BMVARS.wItemSel set)
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_ProcessKey:
	mov		dx, [bp+BMVARS.wItemSel]		; Old selection to DX
	mov		bx, [bp+BMVARS.wItemCnt]		; Item count to BX
	cmp		ah, BMUI_KEY_ENTER
	je		SHORT .Done
	cmp		ah, BMUI_KEY_ESC
	je		SHORT .Cancel
	cmp		ah, BMUI_KEY_UP
	je		SHORT .KeyUp
	cmp		ah, BMUI_KEY_DOWN
	je		SHORT .KeyDown
	cmp		ah, BMUI_KEY_HOME
	je		SHORT .KeyHome
	cmp		ah, BMUI_KEY_END
	je		SHORT .KeyEnd
	cmp		ah, BMUI_KEY_PGUP
	je		SHORT .KeyPgUp
	cmp		ah, BMUI_KEY_PGDN
	je		SHORT .KeyPgDn

	; Drive letter hotkey?
	and		al, ~20h						; To upper case
	cmp		al, 'A'
	jb		SHORT .Ignore
	cmp		al, 'Z'
	ja		SHORT .Ignore
	push	ds
	LOAD_BDA_SEGMENT_TO	ds, cx
	mov		[BOOTVARS.bMenuHotkey], al
	pop		ds
.Done:
	stc
	ret
.Cancel:
	mov		WORD [bp+BMVARS.wItemSel], -1
	stc
	ret
.Ignore:
	clc
	ret

.KeyUp:
	mov		ax, dx
	test	ax, ax							; Already at top?
	jz		SHORT .KeyEnd					;  If so, wrap to last
	dec		ax
	cmp		ax, [bp+BMVARS.wItemTop]		; Need to scroll?
	jae		SHORT .MoveSelection
	mov		[bp+BMVARS.wItemTop], ax
	jmp		SHORT .ScrollTo

.KeyDown:
	mov		ax, dx
	inc		ax
	cmp		ax, bx							; Already at bottom?
	je		SHORT .KeyHome					;  If so, wrap to first
	eMOVZX	cx, BYTE [bp+BMVARS.bVisCnt]
	add		cx, [bp+BMVARS.wItemTop]		; One past last visible
	cmp		ax, cx							; Need to scroll?
	jb		SHORT .MoveSelection
	inc		WORD [bp+BMVARS.wItemTop]
	jmp		SHORT .ScrollTo

.KeyHome:
	xor		ax, ax
	mov		[bp+BMVARS.wItemTop], ax
	jmp		SHORT .ScrollTo

.KeyEnd:
	mov		ax, bx
	dec		ax								; Last menuitem
	mov		cx, bx
	sub		cl, [bp+BMVARS.bVisCnt]
	sbb		ch, 0							; CX = First to show
	jnc		SHORT .StoreTopFromCX
	xor		cx, cx
.StoreTopFromCX:
	mov		[bp+BMVARS.wItemTop], cx
	jmp		SHORT .ScrollTo

.KeyPgUp:
	mov		ax, dx
	div		BYTE [bp+BMVARS.bVisCnt]		; AL = Current page
	sub		al, 1
	jc		SHORT .KeyHome
	mul		BYTE [bp+BMVARS.bVisCnt]		; AX = First on previous page
	mov		[bp+BMVARS.wItemTop], ax
	jmp		SHORT .ScrollTo

.KeyPgDn:
	mov		ax, dx
	div		BYTE [bp+BMVARS.bVisCnt]		; AL = Current page
	inc		ax
	mul		BYTE [bp+BMVARS.bVisCnt]		; AX = First on next page
	eMOVZX	cx, BYTE [bp+BMVARS.bVisCnt]
	add		cx, ax							; One past last on next page
	cmp		cx, bx							; Went over last?
	jae		SHORT .KeyEnd
	mov		[bp+BMVARS.wItemTop], ax
	; Fall to .ScrollTo

	; New selection in AX, visible menuitems scrolled
.ScrollTo:
	mov		[bp+BMVARS.wItemSel], ax
	call	BootMenuUI_SelectionChanged
	call	BootMenuUI_DrawAllMenuitems
	jmp		SHORT .RedrawInfo

	; New selection in AX, old in DX, no scrolling needed
.MoveSelection:
	mov		[bp+BMVARS.wItemSel], ax
	call	BootMenuUI_SelectionChanged
	mov		ax, dx
	call	BootMenuUI_DrawArrowForMenuitemInAX		; Remove old arrow
	mov		ax, [bp+BMVARS.wItemSel]
	call	BootMenuUI_DrawArrowForMenuitemInAX		; Draw new arrow
	call	BootMenuUI_DrawAllDriveNumbers
.RedrawInfo:
	call	BootMenuUI_DrawInfo
	clc
	ret


;--------------------------------------------------------------------
; Updates drive translation and restarts timeout after the selection
; has changed.
;
; BootMenuUI_SelectionChanged
;	Parameters:
;		DS:		RAMVARS segment
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_SelectionChanged:
	push	dx
	mov		ax, [bp+BMVARS.wTimeInit]
	mov		[bp+BMVARS.wTimeLeft], ax
	call	DriveXlate_Reset
	mov		cx, [bp+BMVARS.wItemSel]
	call	BootMenu_ConvertMenuitemToDriveOrFunction
	jc		SHORT .Return					; Function, no translation
	call	DriveXlate_SetDriveToSwap
.Return:
	pop		dx
	ret


;--------------------------------------------------------------------
; Draws the whole menu.
;
; BootMenuUI_DrawMenu
;	Parameters:
;		DS:		RAMVARS segment
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawMenu:
	; Top border
	mov		dh, [bp+BMVARS.bTop]
	mov		bx, (B_TL<<8) | B_H
	mov		al, B_TR
	call	BootMenuUI_DrawBorderLineToRowDH

	; Title
	inc		dh
	mov		cx, MENU_TITLE_LINE_CNT
	call	BootMenuUI_DrawLeftBordersFromRowDH
	mov		dh, [bp+BMVARS.bTop]
	inc		dh
	call	BootMenuUI_StartContentLineAtRowDH
	call	BootMenuPrint_TitleStrings

	; Border between title and menuitems
	mov		dh, [bp+BMVARS.bTop]
	add		dh, MENU_TITLE_LINE_CNT+1
	call	BootMenuUI_DrawMiddleBorderToRowDH

	; Menuitems
	call	BootMenuUI_DrawAllMenuitems

	; Info
	test	BYTE [cs:ROMVARS.wFlags], FLG_ROMVARS_DRVNFO
	jz		SHORT .DrawBottomBorder
	call	BootMenuUI_GetRowForInfoToDH
	dec		dh
	call	BootMenuUI_DrawMiddleBorderToRowDH
	inc		dh
	mov		cx, MENU_INFO_LINE_CNT
	call	BootMenuUI_DrawLeftBordersFromRowDH
	call	BootMenuUI_DrawInfo

	; Bottom border
.DrawBottomBorder:
	call	BootMenuUI_GetRowForBottomBorderToDH
	cmp		WORD [bp+BMVARS.wTimeInit], BYTE 0
	jne		SHORT .DrawBottomBorderWithTimeout
	mov		bx, (B_LL<<8) | B_H
	mov		al, B_LR
	jmp		SHORT BootMenuUI_DrawBorderLineToRowDH
.DrawBottomBorderWithTimeout:
	mov		dl, [bp+BMVARS.bLeft]
	call	BootMenuUI_SetCursorToDX
	mov		dl, B_LL
	PRINT_CHAR
	mov		dl, BHL_TVR
	PRINT_CHAR
	mov		si, g_szTimeout
	call	PrintString_FromCS
	jmp		BootMenuUI_DrawTimeoutDigits


;--------------------------------------------------------------------
; Draws one full-width border line.
;
; BootMenuUI_DrawBorderLineToRowDH
; BootMenuUI_DrawMiddleBorderToRowDH
;	Parameters:
;		AL:		Rightmost character (not for middle border)
;		BH:		Leftmost character (not for middle border)
;		BL:		Middle character (not for middle border)
;		DH:		Row
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DL
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawMiddleBorderToRowDH:
	mov		bx, (BVL_THR<<8) | T_H
	mov		al, THL_BVR
	; Fall to BootMenuUI_DrawBorderLineToRowDH

ALIGN JUMP_ALIGN
BootMenuUI_DrawBorderLineToRowDH:
	push	ax
	mov		dl, [bp+BMVARS.bLeft]
	call	BootMenuUI_SetCursorToDX
	mov		dl, bh
	PRINT_CHAR
	mov		dl, bl
	mov		cx, BMUI_WIDTH-2
	call	BootMenuUI_PrintDLtimesCX
	pop		ax
	mov		dl, al							; Rightmost to DL
	PRINT_CHAR
	ret


;--------------------------------------------------------------------
; Draws the left border and margin for content lines.
;
; BootMenuUI_DrawLeftBordersFromRowDH
;	Parameters:
;		CX:		Number of lines
;		DH:		First row
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		DH:		Row after last line
;	Corrupts registers:
;		AX, CX, DL
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawLeftBordersFromRowDH:
	push	cx
	mov		dl, [bp+BMVARS.bLeft]
	call	BootMenuUI_SetCursorToDX
	mov		dl, B_V
	PRINT_CHAR
	mov		dl, ' '
	PRINT_CHAR
	pop		cx
	inc		dh
	loop	BootMenuUI_DrawLeftBordersFromRowDH
	ret


;--------------------------------------------------------------------
; Content line handling. Content is printed with the normal print
; functions; BootMenuUI_EndContentLine pads the line using the number
; of characters printed since the line was started.
;
; BootMenuUI_StartContentLineAtRowDH
;	Parameters:
;		DH:		Row
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, DX
;
; BootMenuUI_EndContentLine
;	Pads current content line, draws right margin and border and moves
;	to the start of the next content line.
;	Parameters:
;		DH:		Right border character (BootMenuUI_EndContentLineWithBorderInDH only)
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_StartContentLineAtRowDH:
	mov		[bp+BMVARS.bRow], dh
	mov		dl, [bp+BMVARS.bLeft]
	add		dl, BMUI_CONTENT_X
	call	BootMenuUI_SetCursorToDX
	; Fall to BootMenuUI_ClearPrintCount

ALIGN JUMP_ALIGN
BootMenuUI_ClearPrintCount:
	push	ds
	xor		ax, ax
	mov		ds, ax
	mov		[BOOTVARS.bPrintCnt], al
	pop		ds
	ret

ALIGN JUMP_ALIGN
BootMenuUI_EndContentLine:
	mov		dh, B_V
BootMenuUI_EndContentLineWithBorderInDH:
	push	cx
	push	dx
	push	ds
	xor		cx, cx
	mov		ds, cx
	mov		cl, BMUI_CONTENT_W
	sub		cl, [BOOTVARS.bPrintCnt]		; Characters left on line
	pop		ds
	jbe		SHORT .NoPadding
	mov		dl, ' '
	call	BootMenuUI_PrintDLtimesCX
.NoPadding:
	mov		dl, ' '							; Right margin
	PRINT_CHAR
	pop		dx
	mov		dl, dh							; Right border
	PRINT_CHAR
	mov		dh, [bp+BMVARS.bRow]
	inc		dh
	call	BootMenuUI_StartContentLineAtRowDH
	pop		cx
	ret


;--------------------------------------------------------------------
; Draws all visible menuitems.
;
; BootMenuUI_DrawAllMenuitems
;	Parameters:
;		DS:		RAMVARS segment
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawAllMenuitems:
	xor		bx, bx							; Visible line index
.LineLoop:
	push	bx
	mov		dh, [bp+BMVARS.bTop]
	add		dh, MENU_TITLE_LINE_CNT+2
	add		dh, bl							; Row for line
	mov		[bp+BMVARS.bRow], dh
	mov		dl, [bp+BMVARS.bLeft]
	call	BootMenuUI_SetCursorToDX
	mov		dl, B_V
	PRINT_CHAR
	mov		dl, ' '
	PRINT_CHAR
	call	BootMenuUI_ClearPrintCount
	pop		bx
	push	bx
	mov		cx, bx
	add		cx, [bp+BMVARS.wItemTop]		; Menuitem index
	call	BootMenuUI_PrintArrowForMenuitemInCX
	call	BootMenuUI_PrintMenuitemInCX
	pop		bx
	push	bx
	call	BootMenuUI_GetScrollCharForLineBXtoDH
	call	BootMenuUI_EndContentLineWithBorderInDH
	pop		bx
	inc		bx
	cmp		bl, [bp+BMVARS.bVisCnt]
	jb		SHORT .LineLoop
	ret


;--------------------------------------------------------------------
; Prints the selection arrow (or spaces) for a menuitem.
;
; BootMenuUI_PrintArrowForMenuitemInCX
;	Parameters:
;		CX:		Menuitem index
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_PrintArrowForMenuitemInCX:
	mov		dl, ' '
	cmp		cx, [bp+BMVARS.wItemSel]
	jne		SHORT .PrintArrowOrSpace
	mov		dl, RARROW
.PrintArrowOrSpace:
	PRINT_CHAR
	mov		dl, ' '
	PRINT_CHAR
	ret


;--------------------------------------------------------------------
; Redraws the arrow for a menuitem, if it is visible.
;
; BootMenuUI_DrawArrowForMenuitemInAX
;	Parameters:
;		AX:		Menuitem index
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX, DX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawArrowForMenuitemInAX:
	xchg	cx, ax
	call	BootMenuUI_GetRowForMenuitemInCXtoDH
	jnc		SHORT .Return					; Not visible
	mov		dl, [bp+BMVARS.bLeft]
	add		dl, BMUI_CONTENT_X
	call	BootMenuUI_SetCursorToDX
	mov		dl, ' '
	cmp		cx, [bp+BMVARS.wItemSel]
	jne		SHORT .PrintArrowOrSpace
	mov		dl, RARROW
.PrintArrowOrSpace:
	PRINT_CHAR
.Return:
	ret


;--------------------------------------------------------------------
; Redraws drive numbers for all visible drive menuitems. These change
; with drive translation when the selection changes.
;
; BootMenuUI_DrawAllDriveNumbers
;	Parameters:
;		DS:		RAMVARS segment
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawAllDriveNumbers:
	mov		cx, [bp+BMVARS.wItemTop]
	eMOVZX	bx, BYTE [bp+BMVARS.bVisCnt]
.MenuitemLoop:
	push	cx
	push	bx
	call	BootMenuUI_GetRowForMenuitemInCXtoDH
	mov		dl, [bp+BMVARS.bLeft]
	add		dl, BMUI_DRVNUM_X
	push	dx								; Cursor position
	call	BootMenu_ConvertMenuitemToDriveOrFunction
	pop		ax
	jc		SHORT .NextMenuitem				; Function, no drive number
	push	dx								; Drive number
	xchg	dx, ax
	call	BootMenuUI_SetCursorToDX
	pop		dx
	call	BootMenuPrint_TranslatedDriveNumber
.NextMenuitem:
	pop		bx
	pop		cx
	inc		cx
	dec		bx
	jnz		SHORT .MenuitemLoop
	ret


;--------------------------------------------------------------------
; Draws the info lines for the selected menuitem.
;
; BootMenuUI_DrawInfo
;	Parameters:
;		DS:		RAMVARS segment
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawInfo:
	test	BYTE [cs:ROMVARS.wFlags], FLG_ROMVARS_DRVNFO
	jz		SHORT .Return
	push	ds
	push	es
	call	BootMenuUI_GetRowForInfoToDH
	call	BootMenuUI_StartContentLineAtRowDH
	mov		cx, [bp+BMVARS.wItemSel]
	call	RamVars_GetSegmentToDS
	call	BootMenu_ConvertMenuitemToDriveOrFunction
	jc		SHORT .DrawFunctionInfo
	test	dl, 80h
	jz		SHORT .DrawFloppyDriveInfo
	call	BootMenuPrint_HardDiskMenuitemInformation
	jmp		SHORT .InfoDrawn
.DrawFunctionInfo:
	call	BootMenuPrint_FunctionMenuitemInformation
	jmp		SHORT .InfoDrawn
.DrawFloppyDriveInfo:
	call	BootMenuPrint_FloppyMenuitemInformation
.InfoDrawn:
	pop		es
	pop		ds
.Return:
	ret


;--------------------------------------------------------------------
; Prints menuitem string (drive number and name, or function name).
;
; BootMenuUI_PrintMenuitemInCX
;	Parameters:
;		CX:		Menuitem index
;		DS:		RAMVARS segment
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI, DI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_PrintMenuitemInCX:
	push	ds
	push	es
	call	RamVars_GetSegmentToDS
	call	BootMenu_ConvertMenuitemToDriveOrFunction
	jc		SHORT .PrintFunction
	call	BootMenuPrint_TranslatedDriveNumber
	test	dl, 80h
	jz		SHORT .PrintFloppyDrive
	call	BootMenuPrint_HardDiskMenuitem
	jmp		SHORT .Return
.PrintFunction:
	call	BootMenuPrint_FunctionMenuitem
	jmp		SHORT .Return
.PrintFloppyDrive:
	call	BootMenuPrint_FloppyMenuitem
.Return:
	pop		es
	pop		ds
	ret


;--------------------------------------------------------------------
; Redraws the timeout digits if the displayed number of seconds has
; changed. The rest of the bottom border is redrawn only if the number
; of digits has changed.
;
; BootMenuUI_DrawTimeoutDigits
;	Parameters:
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, BX, CX, DX, SI
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_DrawTimeoutDigits:
	mov		ax, 55							; 1 timer tick = 54.945ms
	mul		WORD [bp+BMVARS.wTimeLeft]		; DX:AX = millisecs
	mov		cx, 1024						; ms to s (close enough to 1000)
	div		cx								; 32-bit: delays over 65 s
	mov		bx, [bp+BMVARS.wSecs]
	cmp		ax, bx
	je		SHORT .Return					; Same seconds, nothing to do
	mov		[bp+BMVARS.wSecs], ax
	push	ax
	call	BootMenuUI_GetRowForBottomBorderToDH
	mov		dl, [bp+BMVARS.bLeft]
	add		dl, BMUI_TIMEOUT_X
	call	BootMenuUI_SetCursorToDX
	pop		ax
	push	ax
	call	Print_IntUW						; DX = Digits printed
	pop		ax
	cmp		bx, BYTE -1
	je		SHORT .DrawRestOfBorder			; First draw
	call	BootMenuUI_CountDigitsInAXtoCX	; New digit count
	xchg	ax, bx
	mov		bx, cx
	call	BootMenuUI_CountDigitsInAXtoCX	; Old digit count
	cmp		bx, cx
	je		SHORT .Return					; Same length, done
	mov		dx, bx
.DrawRestOfBorder:
	push	dx								; Digits printed
	mov		dl, 's'
	PRINT_CHAR
	mov		dl, TVL_BHR
	PRINT_CHAR
	pop		ax								; AX = Digits
	mov		cx, BMUI_WIDTH - BMUI_TIMEOUT_X - 3
	sub		cx, ax							; Horizontal border chars left
	mov		dl, B_H
	call	BootMenuUI_PrintDLtimesCX
	mov		dl, B_LR
	PRINT_CHAR
.Return:
	ret


;--------------------------------------------------------------------
; BootMenuUI_CountDigitsInAXtoCX
;	Parameters:
;		AX:		Unsigned value
;	Returns:
;		CX:		Number of decimal digits
;	Corrupts registers:
;		Nothing
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_CountDigitsInAXtoCX:
	mov		cx, 1
	cmp		ax, BYTE 10
	jb		SHORT .Return
	inc		cx
	cmp		ax, BYTE 100
	jb		SHORT .Return
	inc		cx
	cmp		ax, 1000
	jb		SHORT .Return
	inc		cx
	cmp		ax, 10000
	jb		SHORT .Return
	inc		cx
.Return:
	ret


;--------------------------------------------------------------------
; Returns scroll bar character for a visible menuitem line.
;
; BootMenuUI_GetScrollCharForLineBXtoDH
;	Parameters:
;		BX:		Visible line index
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		DH:		Right border character for the line
;	Corrupts registers:
;		AX, BX, CX, DL
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_GetScrollCharForLineBXtoDH:
	mov		ax, [bp+BMVARS.wItemCnt]
	eMOVZX	cx, BYTE [bp+BMVARS.bVisCnt]
	mov		dh, B_V
	cmp		ax, cx							; Need scroll bar?
	jbe		SHORT .Return
	inc		bx								; Next line index
	mul		bx								; DX:AX = Count * next line index
	div		cx								; AX = First menuitem for next line
	dec		ax								; AX = Last menuitem for this line
	mov		dh, FULL_BLCK					; Assume thumb
	sub		ax, [bp+BMVARS.wItemTop]
	jb		SHORT .Track
	cmp		ax, cx
	jb		SHORT .Return					; Visible, thumb
.Track:
	mov		dh, T_V
.Return:
	ret


;--------------------------------------------------------------------
; Row calculations.
;
; BootMenuUI_GetRowForMenuitemInCXtoDH
;	Parameters:
;		CX:		Menuitem index
;		SS:BP:	Ptr to BMVARS
;	Returns:
;		DH:		Row (if visible)
;		CF:		Set if menuitem is visible
;	Corrupts registers:
;		AX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_GetRowForMenuitemInCXtoDH:
	mov		ax, cx
	sub		ax, [bp+BMVARS.wItemTop]
	jb		SHORT .NotVisible
	cmp		al, [bp+BMVARS.bVisCnt]
	jae		SHORT .NotVisible
	mov		dh, [bp+BMVARS.bTop]
	add		dh, MENU_TITLE_LINE_CNT+2
	add		dh, al
	stc
	ret
.NotVisible:
	clc
	ret

ALIGN JUMP_ALIGN
BootMenuUI_GetRowForInfoToDH:
	mov		dh, [bp+BMVARS.bTop]
	add		dh, MENU_TITLE_LINE_CNT+3
	add		dh, [bp+BMVARS.bVisCnt]
	ret

ALIGN JUMP_ALIGN
BootMenuUI_GetRowForBottomBorderToDH:
	mov		dh, [bp+BMVARS.bTop]
	add		dh, MENU_TITLE_LINE_CNT+2
	add		dh, [bp+BMVARS.bVisCnt]
	test	BYTE [cs:ROMVARS.wFlags], FLG_ROMVARS_DRVNFO
	jz		SHORT .Return
	add		dh, MENU_INFO_LINE_CNT+1
.Return:
	ret


;--------------------------------------------------------------------
; BIOS video helpers.
;
; BootMenuUI_SetCursorToDX
;	Parameters:
;		DH:		Row
;		DL:		Column
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX
;
; BootMenuUI_SetCursorShapeToCX
;	Parameters:
;		CX:		Cursor start and end scan lines
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX
;
; BootMenuUI_PrintDLtimesCX
;	Parameters:
;		DL:		Character to print
;		CX:		Number of times to print it
;	Returns:
;		Nothing
;	Corrupts registers:
;		AX, CX
;--------------------------------------------------------------------
ALIGN JUMP_ALIGN
BootMenuUI_SetCursorToDX:
	push	bp
	push	bx
	xor		bx, bx							; Page zero
	mov		ah, 02h							; Set Cursor Position
	int		10h
	pop		bx
	pop		bp
	ret

ALIGN JUMP_ALIGN
BootMenuUI_SetCursorShapeToCX:
	push	bp
	mov		ax, 0103h		; Set Text-Mode Cursor Shape
							; AL=assumed video mode to prevent lock ups on some BIOSes
	int		10h
	pop		bp
	ret

ALIGN JUMP_ALIGN
BootMenuUI_PrintDLtimesCX:
	jcxz	.Return
.PrintLoop:
	PRINT_CHAR
	loop	.PrintLoop
.Return:
	ret
