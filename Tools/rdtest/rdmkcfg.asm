; RDMKCFG.COM - make an RDTEST.CFG by reading a disk on a known-good PC
; Copyright (C) 2026 Glitch Works, LLC
; Released under the GNU General Public License, version 2 only.
;
; The DOS equivalent of Tools/rdtest_cfg.py, for people without Python or
; a way to image disks. Run it on a PC whose disk system is known to
; work, with the disk to be used for testing attached. It reads the
; sector range through INT 13h, checksums each block (the same way
; RDTEST does) and writes the configuration file. Then move the disk,
; RDTEST.COM and the configuration to the PC under test.
;
; usage: RDMKCFG [/D:hh] [/S:start] [/C:count] [/B:block] [/P:passes] [file]
;
;   /D  BIOS drive number, hex (default 80)
;   /S  first LBA, decimal (default 0)
;   /C  sectors to read, decimal, at most 65535. Default: from the first
;       LBA up to the last block that holds any data (at most 65535)
;   /B  sectors per checksum block (default 64)
;   /P  passes for RDTEST to make (default 3)
;   file  configuration file to write (default RDTEST.CFG)
;
; The heads and sectors per track the disk was partitioned with are
; taken from its partition table (the first entry whose start CHS gives
; its start LBA), so RDTEST can warn about a translation mismatch.
;
; Errorlevel: 0 written, 1 read error, 2 bad arguments or geometry,
; 3 the file could not be written, 4 aborted with
; CTRL+C or CTRL+BREAK (any time; RDMKCFG then writes nothing).
;
; 8088 code. Assemble with NASM:  nasm -f bin -o RDMKCFG.COM rdmkcfg.asm

	cpu	8086
	org	100h

MAX_BLOCKS	equ	4096
MAX_COUNT	equ	65535

start:
	cld
	mov	sp, stack_top
	mov	di, msg_title
	call	puts
	mov	di, msg_abort_hint
	call	puts
	call	install_abort_handler
	call	parse_cmdline
	jnc	.args_ok
	mov	di, msg_usage
	call	puts
	mov	al, 2
	jmp	exit
.args_ok:
	call	get_bios_geometry
	jnc	.geo_ok
	mov	al, 2
	jmp	exit
.geo_ok:
	call	fit_range_to_disk
	jnc	.range_ok
	mov	al, 2
	jmp	exit
.range_ok:
	call	partition_geometry
	call	scan
	jnc	.scanned
	mov	al, 1
	jmp	exit
.scanned:
	call	build_text
	call	write_file
	jnc	.written
	mov	al, 3
	jmp	exit
.written:
	call	summary
	xor	al, al
exit:
	mov	ah, 4Ch
	int	21h

;--------------------------------------------------------------------
; Command line. CF set on error (usage shown).
;--------------------------------------------------------------------
parse_cmdline:
	mov	si, 81h
	mov	cl, [80h]
	xor	ch, ch
	add	cx, si
	mov	[text_end], cx
.next:
	call	skip_blanks
	cmp	si, [text_end]
	jae	.done
	lodsb
	cmp	al, 13
	je	.done
	cmp	al, '/'
	je	.switch
	cmp	al, '-'
	je	.switch
	; File name
	dec	si
	mov	di, out_name
	mov	cx, 64
.name:
	cmp	si, [text_end]
	jae	.name_end
	lodsb
	cmp	al, ' '
	jbe	.name_end
	stosb
	loop	.name
	stc
	ret
.name_end:
	xor	al, al
	stosb
	jmp	.next
.switch:
	cmp	si, [text_end]
	jae	.bad
	lodsb
	and	al, ~20h			; Upper case
	mov	bl, al
	cmp	si, [text_end]
	jae	.value
	cmp	byte [si], ':'
	je	.skip_sep
	cmp	byte [si], '='
	jne	.value
.skip_sep:
	inc	si
.value:
	cmp	bl, 'D'
	je	.drive
	cmp	bl, 'S'
	je	.start
	cmp	bl, 'C'
	je	.count
	cmp	bl, 'B'
	je	.block
	cmp	bl, 'P'
	je	.passes
.bad:
	stc
	ret
.drive:
	call	get_hex
	jc	.bad
	mov	[drive], al
	jmp	.next
.start:
	call	get_dec32
	jc	.bad
	mov	[start_lba], ax
	mov	[start_lba+2], dx
	jmp	.next
.count:
	call	get_word_value
	jc	.bad
	mov	[count], ax
	mov	byte [count_given], 1
	jmp	.next
.block:
	call	get_word_value
	jc	.bad
	mov	[blocksize], ax
	jmp	.next
.passes:
	call	get_word_value
	jc	.bad
	test	ah, ah
	jnz	.bad
	mov	[passes], al
	jmp	.next
.done:
	clc
	ret

; Decimal 1...65535 to AX. CF on error.
get_word_value:
	call	get_dec32
	jc	.r
	test	dx, dx
	jnz	.bad
	test	ax, ax
	jnz	.r				; CF clear
.bad:
	stc
.r:	ret

;--------------------------------------------------------------------
; Checks the range against the disk size. Without /C, the range is
; everything from the first LBA, at most MAX_COUNT sectors; scan then
; trims it to the last block holding data. CF on error.
;--------------------------------------------------------------------
fit_range_to_disk:
	mov	ax, [bios_cyls]
	mul	word [heads_x_spt]		; DX:AX = BIOS disk size in sectors
	sub	ax, [start_lba]
	sbb	dx, [start_lba+2]		; DX:AX = sectors from the first LBA
	jc	.beyond
	mov	bx, ax
	or	bx, dx
	jz	.beyond
	test	dx, dx
	jz	.fits_word
	mov	ax, MAX_COUNT
.fits_word:
	cmp	byte [count_given], 0
	jne	.check_given
	mov	[count], ax
	jmp	.check_blocks
.check_given:
	cmp	[count], ax
	ja	.beyond
.check_blocks:
	mov	ax, [count]
	xor	dx, dx
	div	word [blocksize]
	test	dx, dx
	jz	.whole
	inc	ax
.whole:
	cmp	ax, MAX_BLOCKS
	ja	.too_many
	mov	[nblocks], ax
	clc
	ret
.beyond:
	mov	di, msg_beyond_disk
	call	puts
	stc
	ret
.too_many:
	mov	di, msg_too_many
	call	puts
	stc
	ret

;--------------------------------------------------------------------
; Heads and sectors per track from the partition table in LBA 0, if an
; entry's start CHS gives its start LBA. Sets part_heads and part_spt
; (0 if none). A read error just leaves them 0.
;--------------------------------------------------------------------
partition_geometry:
	mov	word [lba], 0
	mov	word [lba+2], 0
	call	read_lba
	jc	.none
	cmp	word [buf+510], 0AA55h
	jne	.none
	mov	si, buf+446
	mov	cx, 4
.entry:
	push	cx
	call	check_entry
	pop	cx
	jnc	.found
	add	si, 16
	loop	.entry
.none:
	mov	word [part_heads], 0
	ret
.found:
	ret

; SI = partition entry. CF clear and part_heads/part_spt set if usable.
check_entry:
	cmp	byte [si+4], 0
	je	.no
	mov	al, [si+5]			; End head
	inc	al
	jz	.no				; 256 heads
	xor	ah, ah
	mov	[part_heads], ax
	mov	al, [si+6]
	and	al, 3Fh				; End sector
	jz	.no
	mov	[part_spt], ax
	; Start CHS
	mov	al, [si+2]
	and	al, 3Fh
	jz	.no				; Sector 0
	cmp	ax, [part_spt]
	ja	.no
	xor	ah, ah
	mov	[start_s], ax
	mov	al, [si+1]
	cmp	ax, [part_heads]
	jae	.no
	mov	[start_h], ax
	mov	al, [si+2]
	and	al, 0C0h
	mov	ah, al
	mov	cl, 6
	shr	ah, cl				; Cylinder bits 9-8
	mov	al, [si+3]
	cmp	ax, 1023
	jae	.no
	; (C * heads + H) * spt + S - 1 must be the start LBA
	mul	word [part_heads]
	add	ax, [start_h]
	adc	dx, 0
	push	ax
	mov	ax, dx
	mul	word [part_spt]
	mov	bx, ax				; High word * spt
	pop	ax
	mul	word [part_spt]
	add	dx, bx
	add	ax, [start_s]
	adc	dx, 0
	sub	ax, 1
	sbb	dx, 0
	cmp	ax, [si+8]
	jne	.no
	cmp	dx, [si+10]
	jne	.no
	clc
	ret
.no:
	stc
	ret

;--------------------------------------------------------------------
; Reads the range and checksums each block. CF on a read error.
;--------------------------------------------------------------------
scan:
	mov	di, msg_reading
	call	puts
	mov	ax, [start_lba]
	mov	[lba], ax
	mov	ax, [start_lba+2]
	mov	[lba+2], ax
	mov	ax, [count]
	mov	[left], ax
	mov	word [block], 0
	mov	word [last_data], -1
.block_loop:
	xor	bx, bx				; Checksum
	mov	byte [has_data], 0
	mov	cx, [blocksize]
	cmp	cx, [left]
	jbe	.n_ok
	mov	cx, [left]
.n_ok:
	sub	[left], cx
.sect_loop:
	push	cx
	push	bx
	call	read_lba
	pop	bx
	jc	.read_error
	; Any data in this sector?
	mov	di, buf
	mov	cx, 256
	xor	ax, ax
	repe	scasw
	je	.empty
	mov	byte [has_data], 1
.empty:
	call	sum_sector
	add	word [lba], 1
	adc	word [lba+2], 0
	pop	cx
	loop	.sect_loop
	mov	si, [block]
	shl	si, 1
	mov	[sums + si], bx
	mov	al, '.'
	cmp	byte [has_data], 0
	je	.mark
	mov	ax, [block]
	mov	[last_data], ax
	mov	al, 'o'
.mark:
	call	putc
	inc	word [block]
	cmp	word [left], 0
	jne	.block_loop
	call	crlf

	cmp	byte [count_given], 0
	jne	.done
	; Trim to the last block with data
	mov	ax, [last_data]
	inc	ax
	jz	.no_data
	mov	[nblocks], ax
	mul	word [blocksize]
	test	dx, dx
	jnz	.done				; Keep the full count
	cmp	ax, [count]
	jae	.done
	mov	[count], ax
.done:
	clc
	ret
.no_data:
	mov	di, msg_no_data
	call	puts
	stc
	ret
.read_error:
	pop	cx
	mov	di, msg_aborted
	call	puts
	stc
	ret

;--------------------------------------------------------------------
; Configuration text into outbuf (out_end = end)
;--------------------------------------------------------------------
build_text:
	mov	di, outbuf
	mov	si, txt_head
	call	emit_str
	mov	al, [drive]
	call	emit_hex8
	mov	si, txt_head2
	call	emit_str
	mov	si, txt_drive
	call	emit_str
	mov	al, [drive]
	call	emit_hex8
	mov	si, txt_start
	call	emit_str
	mov	ax, [start_lba]
	mov	dx, [start_lba+2]
	call	emit_dec32
	mov	si, txt_count
	call	emit_str
	mov	ax, [count]
	xor	dx, dx
	call	emit_dec32
	mov	si, txt_block
	call	emit_str
	mov	ax, [blocksize]
	xor	dx, dx
	call	emit_dec32
	mov	si, txt_passes
	call	emit_str
	mov	al, [passes]
	xor	ah, ah
	xor	dx, dx
	call	emit_dec32
	cmp	word [part_heads], 0
	je	.sums
	mov	si, txt_heads
	call	emit_str
	mov	ax, [part_heads]
	xor	dx, dx
	call	emit_dec32
	mov	si, txt_spt
	call	emit_str
	mov	ax, [part_spt]
	xor	dx, dx
	call	emit_dec32
.sums:
	xor	bx, bx				; Block number
.sum_line:
	cmp	bx, [nblocks]
	jae	.end
	mov	si, txt_sum
	call	emit_str
	mov	cx, 8
.sum_value:
	push	bx
	shl	bx, 1
	mov	ax, [sums + bx]
	pop	bx
	push	ax
	mov	al, ah
	call	emit_hex8
	pop	ax
	call	emit_hex8
	inc	bx
	cmp	bx, [nblocks]
	jae	.end
	dec	cx
	jz	.sum_line
	mov	al, ' '
	stosb
	jmp	.sum_value
.end:
	mov	ax, 0A0Dh
	stosw
	mov	[out_end], di
	ret

emit_str:					; SI = zero-terminated
	lodsb
	test	al, al
	jz	.r
	stosb
	jmp	emit_str
.r:	ret

emit_hex8:					; AL
	push	ax
	push	cx
	mov	cl, 4
	push	ax
	shr	al, cl
	call	.nib
	pop	ax
	call	.nib
	pop	cx
	pop	ax
	ret
.nib:
	and	al, 0Fh
	add	al, '0'
	cmp	al, '9'
	jbe	.p
	add	al, 7
.p:	stosb
	ret

emit_dec32:					; DX:AX
	push	bx
	push	cx
	mov	bx, 10
	xor	cx, cx
.div:
	push	ax				; DX:AX / 10, remainder to stack
	mov	ax, dx
	xor	dx, dx
	div	bx
	mov	si, ax				; High word of quotient
	pop	ax
	div	bx
	push	dx
	inc	cx
	mov	dx, si
	mov	si, ax
	or	si, dx
	jnz	.div
.out:
	pop	ax
	add	al, '0'
	stosb
	loop	.out
	pop	cx
	pop	bx
	ret

;--------------------------------------------------------------------
; Writes outbuf to the file. CF on error (message shown).
;--------------------------------------------------------------------
write_file:
	mov	ah, 3Ch				; Create (or truncate)
	xor	cx, cx
	mov	dx, out_name
	int	21h
	jc	.error
	mov	bx, ax
	mov	ah, 40h
	mov	cx, [out_end]
	sub	cx, outbuf
	mov	dx, outbuf
	int	21h
	jc	.error_close
	cmp	ax, cx
	jne	.error_close			; Disk full
	mov	ah, 3Eh
	int	21h
	jc	.error
	ret
.error_close:
	mov	ah, 3Eh
	int	21h
.error:
	mov	di, msg_write_error
	call	puts
	mov	di, out_name
	call	puts
	call	crlf
	stc
	ret

summary:
	mov	di, msg_wrote
	call	puts
	mov	di, out_name
	call	puts
	mov	di, msg_lba
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
	call	crlf
	cmp	word [part_heads], 0
	je	.no_geo
	mov	di, msg_part_geo
	call	puts
	mov	ax, [part_heads]
	call	putdec16
	mov	al, '/'
	call	putc
	mov	ax, [part_spt]
	call	putdec16
	call	crlf
	ret
.no_geo:
	mov	di, msg_no_geo
	jmp	puts

%include "common.inc"

;--------------------------------------------------------------------
; Data
;--------------------------------------------------------------------
msg_title	db	'RDMKCFG: make an RDTEST configuration from a disk (Rivet project)', 13, 10, 0
msg_usage	db	'usage: RDMKCFG [/D:hh] [/S:start] [/C:count] [/B:block] [/P:passes] [file]', 13, 10
		db	'  Reads the disk on this (known-good) PC and writes RDTEST.CFG', 13, 10
		db	'  (or the file named) for RDTEST to check another PC with.', 13, 10, 0
msg_beyond_disk	db	'The range is past the end of the disk', 13, 10, 0
msg_too_many	db	'Too many blocks: use a larger /B or a smaller /C', 13, 10, 0
msg_reading	db	'Reading (o = block with data, . = empty):', 13, 10, 0
msg_no_data	db	'No data found in the range', 13, 10, 0
msg_aborted	db	'Read error: no configuration written. Use a PC whose disk', 13, 10
		db	'system is known to work.', 13, 10, 0
msg_write_error	db	'Cannot write ', 0
msg_wrote	db	'Wrote ', 0
msg_lba		db	': LBA ', 0
msg_count	db	'h, ', 0
msg_blocks	db	' sectors, blocks: ', 0
msg_part_geo	db	'Partitioned with heads/sectors: ', 0
msg_no_geo	db	'No usable partition table: no geometry check in RDTEST', 13, 10, 0

txt_head	db	'; RDTEST.CFG made by RDMKCFG from BIOS drive ', 0
txt_head2	db	'h', 13, 10, 0
txt_drive	db	'DRIVE=', 0
txt_start	db	13, 10, 'START=', 0
txt_count	db	13, 10, 'COUNT=', 0
txt_block	db	13, 10, 'BLOCK=', 0
txt_passes	db	13, 10, 'PASSES=', 0
txt_heads	db	13, 10, 'HEADS=', 0
txt_spt		db	13, 10, 'SPT=', 0
txt_sum		db	13, 10, 'SUM=', 0

out_name	db	'RDTEST.CFG', 0
		times 64 - ($ - out_name) db 0
		db	0

	align	2
drive		db	80h
passes		db	3
count_given	db	0
has_data	db	0
bios_spt	db	0
		db	0
bios_heads	dw	0
bios_cyls	dw	0
heads_x_spt	dw	0
start_lba	dd	0
lba		dd	0
count		dw	0
blocksize	dw	64
nblocks		dw	0
left		dw	0
block		dw	0
last_data	dw	0
part_heads	dw	0
part_spt	dw	0
start_h		dw	0
start_s		dw	0
text_end	dw	0
out_end		dw	0

	align	16
	absolute $
buf:		resb	512
sums:		resb	MAX_BLOCKS * 2
outbuf:		resb	MAX_BLOCKS * 5 + 512
		resb	512
stack_top:
