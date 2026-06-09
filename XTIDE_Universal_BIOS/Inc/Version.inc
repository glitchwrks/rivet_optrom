; Project name	:	XTIDE Universal BIOS
; Description	:	Version information.

;
; XTIDE Universal BIOS and Associated Tools
; Copyright (C) 2009-2010 by Tomi Tilli, 2011-2026 by XTIDE Universal BIOS Team.
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

; Flash signature revisions:
; XUB212	Added a proper ROMVARS flag for MODULE_MFM_COMPATIBILITY (FLG_ROMVARS_MODULE_MFM_COMPATIBILITY).
;			Added 5 new color themes.
; XUB211	Added device type DEVICE_8BIT_JUKO_D16X
; XUB210	Moved pColorTheme so it's not copied when loading old settings from EEPROM.
;			Added wRamVars to allow use of UMBs for storing variables in Full operating mode.
;			Increased the length of szTitle and decreased the length of szVersion for USE_PS2
; XUB209	Shortened the BIOS version string (ROMVARS.szVersion) and WORD aligned the IDEVARS structures
; XUB208	Added option to skip slave drive detection
; XTIDE207	Added device type DEVICE_8BIT_XTIDE_REV2_OLIVETTI
; XTIDE206	Added support for Color Themes
; XTIDE205	Added DEVICE_8BIT_XTCF_PIO16_WITH_BIU_OFFLOAD after other XT-CF
;			PIO modes (prevents empty indexes in PIO jump tables)
;

%ifndef VERSION_INC
%define VERSION_INC


%define TITLE_STRING_START		"-=XTIDE Universal BIOS "
%ifdef USE_PS2
	%define TITLE_STRING_END	"(PS/2)=-"
%elifdef USE_AT
	%ifdef USE_386
		%define TITLE_STRING_END	"(386)=-"
	%else
		%define TITLE_STRING_END	"(AT)=-"
	%endif
%elifdef USE_386
	%define TITLE_STRING_END	"(386)=-"
%elifdef USE_186
	%define TITLE_STRING_END	"(XT+)=-"
%else
	%define TITLE_STRING_END	"(XT)=-"
%endif

%define TITLE_STRING			TITLE_STRING_START,TITLE_STRING_END,NULL
%define ROM_VERSION_STRING		incbin "Revision.inc"	; This file must include a trailing space
; Note!
; NASM will throw weird errors when using ROM_VERSION_STRING if it's not a single statement on its own line.
; This is likely due to the "unusual" way it is defined above. Make sure to not have any additional strings
; on the same line, either before or after. In fact, do not even put a preceding label on the same line!
%define BUILD_DATE_STRING		"(",__DATE__,")"
%define FLASH_SIGNATURE			"XUB212"	; Also known as the ROMVARS version. Do not terminate with NULL.


%endif ; VERSION_INC
