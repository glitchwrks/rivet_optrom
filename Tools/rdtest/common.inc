;--------------------------------------------------------------------
; common.inc - code shared by RDTEST and RDMKCFG
; Copyright (C) 2026 Glitch Works, LLC
; Released under the GNU General Public License, version 2 only.
;
; The including program defines these variables:
;	drive (byte), lba (dword), bios_spt (byte), bios_heads (word),
;	bios_cyls (word), heads_x_spt (word), text_end (word),
;	buf (512 bytes)
; and, in a build with BOOT defined, errorlevel (byte).
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Geometry of [drive] from INT 13h AH=08h, printed.
; Sets bios_spt, bios_heads, bios_cyls and heads_x_spt. CF on error.
;--------------------------------------------------------------------
get_bios_geometry:
	mov	dl, [drive]
	mov	ah, 08h
	push	es
	int	13h
	pop	es
	jc	.fail
	mov	al, cl
	and	al, 3Fh
	jz	.fail
	mov	[bios_spt], al
	mov	al, dh
	xor	ah, ah
	inc	ax
	mov	[bios_heads], ax
	xchg	ch, cl				; Cylinders: CL bits 7-6 are 9-8
	rol	ch, 1
	rol	ch, 1
	and	ch, 3
	inc	cx
	mov	[bios_cyls], cx
	mov	di, msg_geo
	call	puts
	mov	ax, [bios_cyls]
	call	putdec16
	mov	al, '/'
	call	putc
	mov	ax, [bios_heads]
	call	putdec16
	mov	al, '/'
	call	putc
	mov	al, [bios_spt]
	xor	ah, ah
	call	putdec16
	call	crlf
	mov	al, [bios_spt]
	xor	ah, ah
	mul	word [bios_heads]		; Heads 1...256
	mov	[heads_x_spt], ax
	clc
	ret
.fail:
	mov	di, msg_geofail
	call	puts
	stc
	ret

;--------------------------------------------------------------------
; Adds the 512 bytes at buf to the block checksum in BX: for each
; little-endian word, rotate BX left by one and add the word.
; Corrupts AX, CX, SI.
;--------------------------------------------------------------------
sum_sector:
	mov	si, buf
	mov	cx, 256
.loop:
	lodsw
	rol	bx, 1
	add	bx, ax
	loop	.loop
	ret

;--------------------------------------------------------------------
; Reads LBA [lba] into buf. CF set on error (message printed).
;--------------------------------------------------------------------
read_lba:
	; Cylinder/head/sector from the BIOS geometry
	mov	ax, [lba+2]
	xor	dx, dx
	div	word [heads_x_spt]		; High word first
	test	ax, ax
	jnz	.beyond
	mov	ax, [lba]
	div	word [heads_x_spt]		; AX = cylinder, DX = rest
	cmp	ax, 1023
	ja	.beyond
	mov	cx, ax				; Cylinder
	mov	ax, dx
	div	byte [bios_spt]			; AL = head, AH = sector - 1
	mov	dh, al
	xchg	ch, cl				; CH = cylinder bits 7-0
	ror	cl, 1
	ror	cl, 1				; Cylinder bits 9-8 to CL 7-6
	and	cl, 0C0h
	inc	ah
	or	cl, ah
	mov	dl, [drive]
	mov	bx, buf
	mov	ax, 0201h
	push	es
	push	ds
	pop	es
	int	13h
	pop	es
	jc	.error
	ret
.error:
	push	ax
	mov	di, msg_rderr
	call	puts
	call	put_lba
	mov	di, msg_status
	call	puts
	pop	ax
	mov	al, ah
	call	puthex8
	mov	al, 'h'
	call	putc
	call	crlf
	stc
	ret
.beyond:
	mov	di, msg_beyond
	call	puts
	call	put_lba
	call	crlf
	stc
	ret


skip_blanks:
	cmp	si, [text_end]
	jae	.done
	cmp	byte [si], ' '
	je	.next
	cmp	byte [si], 9
	jne	.done
.next:
	inc	si
	jmp	skip_blanks
.done:
	ret


; Hex number at SI to AX (at least one digit). CF on error.
get_hex:
	call	skip_blanks
	xor	dx, dx
	xor	cx, cx				; Digit count
.digit:
	cmp	si, [text_end]
	jae	.end
	mov	al, [si]
	sub	al, '0'
	cmp	al, 9
	jbe	.add
	mov	al, [si]
	and	al, ~20h
	sub	al, 'A'
	cmp	al, 5
	ja	.end
	add	al, 10
.add:
	push	cx
	mov	cl, 4
	shl	dx, cl
	pop	cx
	or	dl, al
	inc	si
	inc	cx
	jmp	.digit
.end:
	mov	ax, dx
	cmp	cx, 1
	jb	.r				; CF set if no digits
	clc
.r:	ret

; Decimal number at SI to DX:AX. CF on error (no digits).
get_dec32:
	call	skip_blanks
	xor	ax, ax
	xor	dx, dx
	xor	cx, cx
.digit:
	cmp	si, [text_end]
	jae	.end
	mov	bl, [si]
	sub	bl, '0'
	cmp	bl, 9
	ja	.end
	; DX:AX = DX:AX * 10 + BL
	push	bx
	push	cx
	mov	bx, ax
	mov	cx, dx
	shl	ax, 1
	rcl	dx, 1				; * 2
	shl	ax, 1
	rcl	dx, 1				; * 4
	add	ax, bx
	adc	dx, cx				; * 5
	shl	ax, 1
	rcl	dx, 1				; * 10
	pop	cx
	pop	bx
	xor	bh, bh
	add	ax, bx
	adc	dx, 0
	inc	si
	inc	cx
	jmp	.digit
.end:
	cmp	cx, 1
	jb	.r
	clc
.r:	ret

;--------------------------------------------------------------------
; Output: DOS (redirectable) or BIOS teletype in the BOOT build
;--------------------------------------------------------------------
putc:
	push	ax
	push	dx
%ifdef BOOT
	push	bx
	mov	ah, 0Eh
	xor	bx, bx
	int	10h
	pop	bx
%else
	mov	dl, al
	mov	ah, 02h
	int	21h
%endif
	pop	dx
	pop	ax
	ret
puts:						; DI = zero-terminated string
	mov	al, [di]
	test	al, al
	jz	.done
	call	putc
	inc	di
	jmp	puts
.done:
	ret
crlf:
	mov	al, 13
	call	putc
	mov	al, 10
	jmp	putc
put_lba:
	mov	ax, [lba]
	mov	dx, [lba+2]
puthex32:					; DX:AX
	push	ax
	mov	ax, dx
	call	puthex16
	pop	ax
puthex16:
	push	ax
	mov	al, ah
	call	puthex8
	pop	ax
puthex8:
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
.p:	jmp	putc
putdec16:					; AX
	push	ax
	push	bx
	push	cx
	push	dx
	mov	bx, 10
	xor	cx, cx
.div:
	xor	dx, dx
	div	bx
	push	dx
	inc	cx
	test	ax, ax
	jnz	.div
.out:
	pop	ax
	add	al, '0'
	call	putc
	loop	.out
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret


msg_geo		db	'BIOS geometry (cylinders/heads/sectors): ', 0
msg_geofail	db	'INT 13h AH=08h failed for this drive', 13, 10, 0
msg_rderr	db	13, 10, 'Read error at LBA ', 0
msg_status	db	'h, status ', 0
msg_beyond	db	13, 10, 'Beyond cylinder 1023: LBA ', 0
