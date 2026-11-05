; RDTEST.COM - disk read checkout tool for Rivet / XT-IDE systems
; Copyright (C) 2026 Glitch Works, LLC
; Released under the GNU General Public License, version 2 only.
;
; Reads a range of sectors from a BIOS hard disk through INT 13h, several
; times, and compares a checksum of each block of sectors with values
; from a configuration file made from a known-good disk image
; (Tools/rdtest_cfg.py). Mismatches mean the data reaching the PC is not
; what is on the disk: a controller, connector, cable or card problem.
;
; usage: RDTEST [config file]      (default RDTEST.CFG)
;
; Errorlevel: 0 all passes match, 1 mismatch or read error, 2 bad
; configuration or geometry, 3 configuration file not found.
;
; Checksum of a block: start at 0; for each little-endian word of each
; sector, rotate the 16-bit sum left by one and add the word.
;
; 8088 code. Assemble with NASM:  nasm -f bin -o RDTEST.COM rdtest.asm
; With -DBOOT it runs from a boot sector instead, with the configuration
; included at build time from rdtest.cfg (used by the emulator tests).

	cpu	8086
%ifdef BOOT
	org	7C00h
%else
	org	100h
%endif

MAX_BLOCKS	equ	4096
CFG_SIZE	equ	8192

start:
	cld
%ifdef BOOT
	xor	ax, ax
	mov	ds, ax
	mov	es, ax
	mov	ss, ax
	mov	sp, 7C00h
	mov	si, embedded_cfg
	mov	cx, embedded_cfg_end - embedded_cfg
%else
	mov	sp, stack_top
%endif
	mov	di, msg_title
	call	puts
%ifndef BOOT
	call	read_cfg_file			; SI = text, CX = length
%endif
	call	parse_cfg
	jnc	.cfg_ok
	mov	al, 2
	jmp	exit
.cfg_ok:
	call	show_cfg
	call	check_geometry
	jnc	.geo_ok
	mov	al, 2
	jmp	exit
.geo_ok:
	mov	byte [errorlevel], 0
	mov	byte [pass], 1
.pass_loop:
	call	run_pass
	inc	byte [pass]
	mov	al, [pass]
	cmp	al, [passes]
	jbe	.pass_loop
	mov	di, msg_summary_ok
	cmp	byte [errorlevel], 0
	je	.summary
	mov	di, msg_summary_bad
.summary:
	call	puts
	mov	al, [errorlevel]
	jmp	exit

;--------------------------------------------------------------------
; One pass over all blocks
;--------------------------------------------------------------------
run_pass:
	mov	di, msg_pass
	call	puts
	mov	al, [pass]
	xor	ah, ah
	call	putdec16
	mov	al, ':'
	call	putc
	mov	word [bad_blocks], 0
	mov	ax, [start_lba]
	mov	[lba], ax
	mov	ax, [start_lba+2]
	mov	[lba+2], ax
	mov	ax, [count]
	mov	[left], ax
	mov	word [block], 0
.block_loop:
	mov	word [cksum], 0
	mov	byte [blk_err], 0
	mov	cx, [blocksize]
	cmp	cx, [left]
	jbe	.n_ok
	mov	cx, [left]			; Last, partial block
.n_ok:
	sub	[left], cx
.sect_loop:
	push	cx
	call	read_lba
	jnc	.sum
	mov	byte [blk_err], 1		; Count it, keep going
	jmp	.next_sect
.sum:
	mov	bx, [cksum]
	call	sum_sector
	mov	[cksum], bx
.next_sect:
	add	word [lba], 1
	adc	word [lba+2], 0
	pop	cx
	loop	.sect_loop

	; Compare
	mov	si, [block]
	shl	si, 1
	mov	ax, [cksum]
	cmp	byte [blk_err], 0
	jne	.bad
	cmp	ax, [sums + si]
	jne	.bad
	mov	al, '.'
	call	putc
	jmp	.next_block
.bad:
	inc	word [bad_blocks]
	mov	byte [errorlevel], 1
	mov	al, 'E'
	cmp	byte [blk_err], 0
	jne	.mark
	mov	al, 'X'
.mark:
	call	putc
.next_block:
	inc	word [block]
	cmp	word [left], 0
	jne	.block_loop
	call	crlf
	cmp	word [bad_blocks], 0
	je	.pass_ok
	call	list_bad_blocks
	ret
.pass_ok:
	ret

; Prints how many blocks were bad in this pass (the marks on the pass
; line show which)
list_bad_blocks:
	mov	di, msg_bad_count
	call	puts
	mov	ax, [bad_blocks]
	call	putdec16
	mov	di, msg_bad_tail
	call	puts
	ret

;--------------------------------------------------------------------
; Geometry from INT 13h AH=08h, compared with the configuration
;--------------------------------------------------------------------
check_geometry:
	call	get_bios_geometry
	jc	.r
	; Compare with the configuration, if it has a geometry
	cmp	word [cfg_heads], 0
	je	.ok
	mov	ax, [cfg_heads]
	cmp	ax, [bios_heads]
	jne	.mismatch
	mov	ax, [cfg_spt]
	cmp	al, [bios_spt]
	je	.ok
.mismatch:
	mov	di, msg_geo_warn1
	call	puts
	mov	ax, [cfg_heads]
	call	putdec16
	mov	al, '/'
	call	putc
	mov	ax, [cfg_spt]
	call	putdec16
	mov	di, msg_geo_warn2
	call	puts
.ok:
	clc
.r:	ret

;--------------------------------------------------------------------
; Configuration
;--------------------------------------------------------------------
show_cfg:
	mov	di, msg_drive
	call	puts
	mov	al, [drive]
	call	puthex8
	mov	di, msg_from
	call	puts
	mov	ax, [start_lba]
	mov	dx, [start_lba+2]
	call	puthex32
	mov	di, msg_count
	call	puts
	mov	ax, [count]
	call	putdec16
	mov	di, msg_blocks
	call	puts
	mov	ax, [nblocks]
	call	putdec16
	mov	di, msg_of
	call	puts
	mov	ax, [blocksize]
	call	putdec16
	mov	di, msg_passes
	call	puts
	mov	al, [passes]
	xor	ah, ah
	call	putdec16
	call	crlf
	ret

%ifndef BOOT
; Reads the configuration file into cfg_buf. SI = text, CX = length.
read_cfg_file:
	; Name from the command line, or RDTEST.CFG
	mov	si, 81h
	mov	di, cfg_name_buf
	mov	cl, [80h]
	xor	ch, ch
.skip:
	jcxz	.default
	lodsb
	dec	cx
	cmp	al, ' '
	je	.skip
	cmp	al, 9
	je	.skip
.copy:
	cmp	al, ' '
	jbe	.named
	stosb
	jcxz	.named
	lodsb
	dec	cx
	jmp	.copy
.named:
	xor	al, al
	stosb
	mov	dx, cfg_name_buf
	jmp	.open
.default:
	mov	dx, cfg_default
.open:
	mov	ax, 3D00h			; Open, read only
	int	21h
	jc	.not_found
	mov	bx, ax
	mov	ah, 3Fh
	mov	cx, CFG_SIZE
	mov	dx, cfg_buf
	int	21h
	jc	.not_found
	push	ax
	mov	ah, 3Eh
	int	21h
	pop	cx
	mov	si, cfg_buf
	ret
.not_found:
	mov	di, msg_nocfg
	call	puts
	mov	al, 3
	jmp	exit
%endif

; Parses the configuration text at SI (CX bytes). CF set on error.
parse_cfg:
	mov	[text_end], si
	add	[text_end], cx
	mov	byte [drive], 80h
	mov	byte [passes], 3
	mov	word [blocksize], 64
	mov	word [nsums], 0
.line:
	call	skip_blanks
	cmp	si, [text_end]
	jae	.done
	lodsb
	cmp	al, ';'
	je	.skip_line
	cmp	al, '#'
	je	.skip_line
	cmp	al, 13
	je	.line
	cmp	al, 10
	je	.line
	dec	si
	; Key: compare with each known key
	mov	bx, keys
.try_key:
	mov	di, [bx]
	test	di, di
	jz	.unknown
	push	si
	call	match_key			; ZF if key at SI matches DI
	jz	.found
	pop	si
	add	bx, 4
	jmp	.try_key
.found:
	add	sp, 2				; Drop saved SI
	call	skip_blanks
	cmp	si, [text_end]
	jae	.syntax
	lodsb
	cmp	al, '='
	jne	.syntax
	call	[bx+2]				; Value handler, CF on error
	jc	.syntax
.skip_line:
	cmp	si, [text_end]
	jae	.done
	lodsb
	cmp	al, 10
	jne	.skip_line
	jmp	.line
.unknown:
.syntax:
	mov	di, msg_syntax
	call	puts
	stc
	ret
.done:
	; Checks
	cmp	word [count], 0
	je	.missing
	cmp	word [blocksize], 0
	je	.missing
	mov	ax, [count]
	xor	dx, dx
	div	word [blocksize]
	test	dx, dx
	jz	.whole
	inc	ax
.whole:
	mov	[nblocks], ax
	cmp	ax, [nsums]
	jne	.sum_count
	cmp	byte [passes], 0
	je	.missing
	clc
	ret
.missing:
	mov	di, msg_missing
	call	puts
	stc
	ret
.sum_count:
	mov	di, msg_sumcount
	call	puts
	stc
	ret

; ZF set if the text at SI starts with the key at DI (letters, any case),
; followed by a non-letter. SI advanced past the key if so.
match_key:
	mov	al, [di]
	test	al, al
	jz	.end_of_key
	cmp	si, [text_end]
	jae	.no
	mov	ah, [si]
	and	ah, ~20h			; Upper case
	cmp	ah, al
	jne	.no
	inc	si
	inc	di
	jmp	match_key
.end_of_key:
	cmp	si, [text_end]
	jae	.yes
	mov	al, [si]
	and	al, ~20h
	cmp	al, 'A'
	jb	.yes
	cmp	al, 'Z'
	jbe	.no
.yes:
	xor	al, al				; ZF = 1
	ret
.no:
	or	al, 1				; ZF = 0
	ret

; Value handlers: SI at the value. CF on error.
val_drive:
	call	get_hex
	jc	.r
	mov	[drive], al
.r:	ret
val_start:
	call	get_dec32
	jc	.r
	mov	[start_lba], ax
	mov	[start_lba+2], dx
.r:	ret
val_count:
	call	get_dec32
	jc	.r
	test	dx, dx
	stc
	jnz	.r				; At most 65535
	mov	[count], ax
	clc
.r:	ret
val_block:
	call	get_dec32
	jc	.r
	test	dx, dx
	stc
	jnz	.r
	mov	[blocksize], ax
	clc
.r:	ret
val_passes:
	call	get_dec32
	jc	.r
	test	dx, dx
	stc
	jnz	.r
	test	ah, ah
	stc
	jnz	.r
	mov	[passes], al
	clc
.r:	ret
val_heads:
	call	get_dec32
	jc	.r
	mov	[cfg_heads], ax
.r:	ret
val_spt:
	call	get_dec32
	jc	.r
	mov	[cfg_spt], ax
.r:	ret
val_sum:
.next:
	call	skip_blanks
	cmp	si, [text_end]
	jae	.done
	mov	al, [si]
	cmp	al, ';'
	je	.done
	cmp	al, 13
	je	.done
	cmp	al, 10
	je	.done
	call	get_hex
	jc	.r
	mov	bx, [nsums]
	cmp	bx, MAX_BLOCKS
	jae	.full
	shl	bx, 1
	mov	[sums + bx], ax
	inc	word [nsums]
	jmp	.next
.full:
	stc
	ret
.done:
	clc
.r:	ret

exit:						; AL = errorlevel
%ifdef BOOT
	mov	[errorlevel], al
	int	18h
%else
	mov	ah, 4Ch
	int	21h
%endif

%include "common.inc"

;--------------------------------------------------------------------
; Data
;--------------------------------------------------------------------
keys:
	dw	k_drive, val_drive
	dw	k_start, val_start
	dw	k_count, val_count
	dw	k_block, val_block
	dw	k_passes, val_passes
	dw	k_heads, val_heads
	dw	k_spt, val_spt
	dw	k_sum, val_sum
	dw	0
k_drive		db	'DRIVE', 0
k_start		db	'START', 0
k_count		db	'COUNT', 0
k_block		db	'BLOCK', 0
k_passes	db	'PASSES', 0
k_heads		db	'HEADS', 0
k_spt		db	'SPT', 0
k_sum		db	'SUM', 0

msg_title	db	'RDTEST disk read check (Rivet project)', 13, 10, 0
msg_drive	db	'Drive ', 0
msg_from	db	'h, LBA ', 0
msg_count	db	'h, ', 0
msg_blocks	db	' sectors in ', 0
msg_of		db	' blocks of ', 0
msg_passes	db	', passes: ', 0
msg_geo_warn1	db	'WARNING: the image was made with ', 0
msg_geo_warn2	db	' heads/sectors. Data is still', 13, 10
		db	'checked by LBA, but DOS on this disk will not work with', 13, 10
		db	'this BIOS geometry (check the translation mode).', 13, 10, 0
msg_pass	db	'Pass ', 0
msg_bad_count	db	'  ', 0
msg_bad_tail	db	' block(s) bad (X = wrong data, E = read error)', 13, 10, 0
msg_summary_ok	db	'All passes match the image.', 13, 10, 0
msg_summary_bad	db	'FAILED: data read does not match the image.', 13, 10, 0
msg_syntax	db	'Configuration: unknown key or bad value', 13, 10, 0
msg_missing	db	'Configuration: COUNT, BLOCK and PASSES must not be 0', 13, 10, 0
msg_sumcount	db	'Configuration: number of SUM values does not match COUNT/BLOCK', 13, 10, 0
%ifndef BOOT
msg_nocfg	db	'Cannot open configuration file (default RDTEST.CFG)', 13, 10, 0
cfg_default	db	'RDTEST.CFG', 0
%endif

%ifdef BOOT
embedded_cfg:
	incbin	"rdtest.cfg"
embedded_cfg_end:
%endif

	align	2
errorlevel	db	0
pass		db	0
passes		db	0
drive		db	0
bios_spt	db	0
blk_err		db	0
bios_heads	dw	0
bios_cyls	dw	0
heads_x_spt	dw	0
cfg_heads	dw	0
cfg_spt		dw	0
start_lba	dd	0
lba		dd	0
count		dw	0
blocksize	dw	0
nblocks		dw	0
nsums		dw	0
left		dw	0
block		dw	0
bad_blocks	dw	0
cksum		dw	0
text_end	dw	0

	align	16
	absolute $				; Uninitialized: not in the file
buf:		resb	512
%ifndef BOOT
cfg_name_buf:	resb	128
cfg_buf:	resb	CFG_SIZE
%endif
sums:		resb	MAX_BLOCKS * 2
		resb	512
stack_top:
