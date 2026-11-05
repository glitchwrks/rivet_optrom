#!/usr/bin/env python3
# Rivet: CHS translation mode tests on the emulated XT.
# Copyright (C) 2026 Glitch Works, LLC
# Released under the GNU General Public License, version 2 only.
"""Checks the L-CHS geometry (INT 13h AH=08h) and the CHS -> sector
mapping (INT 13h AH=02h) for each CHS translation mode.

A small test program in the drive's boot sector asks for the geometry,
reads a list of CHS addresses, and records which sector each read
returned (every other sector holds its own LBA). The results are
compared with a Python model of each mode."""

import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xtemu  # noqa: E402

ROMVARS_IDEVARS0 = 0x60
IDEVARS_SIZE = 26
DRVPARAMS_MASTER = 10         # IDEVARS.drvParamsMaster
DRVPARAMS_XLATE_MODE = 2      # DRVPARAMS.bXlateMode


def xlate_mode_offset(rom):
    """Offset of bXlateMode for the master drive of the XT-IDE at 300h."""
    for i in range(5):
        ide = ROMVARS_IDEVARS0 + i * IDEVARS_SIZE
        if int.from_bytes(rom[ide:ide + 2], 'little') == 0x300:
            return ide + DRVPARAMS_MASTER + DRVPARAMS_XLATE_MODE
    raise ValueError('no controller at 300h')
RIVET, NONE, LBA_ASSIST, LBA_255 = 0, 1, 2, 3
MODE_NAMES = {RIVET: 'rivet', NONE: 'none', LBA_ASSIST: 'assist', LBA_255: '255'}

RESULTS = 0x7E00              # AH=08h CX, DX, AX; then 8 bytes per read
TABLE_OFS = 0x100             # CHS table inside the boot sector

PROGRAM = """
	cpu	8086
	org	7C00h
	xor	ax, ax
	mov	ds, ax
	mov	es, ax
	mov	ss, ax
	mov	sp, 7C00h
	mov	dl, 80h
	mov	ah, 08h
	int	13h
	mov	[7E00h], cx
	mov	[7E02h], dx
	mov	[7E04h], ax
	mov	si, 7C00h + %d
	lodsw
	mov	bp, ax			; Number of reads
	mov	di, 7E10h
.next:
	lodsw
	mov	cx, ax
	lodsw
	mov	dh, ah			; Head
	mov	dl, 80h
	mov	bx, 8000h
	mov	word [bx], 0FFFFh
	mov	word [bx+2], 0FFFFh
	push	si
	push	di
	push	bp
	mov	ax, 0201h
	int	13h
	pop	bp
	pop	di
	pop	si
	mov	[di+4], ax		; Status
	sbb	ax, ax
	mov	[di+6], ax		; FFFFh if CF set
	mov	ax, [8000h]
	mov	[di], ax
	mov	ax, [8002h]
	mov	[di+2], ax
	add	di, 8
	dec	bp
	jnz	.next
	int	18h
""" % TABLE_OFS


def assemble():
    with tempfile.TemporaryDirectory() as d:
        src, out = os.path.join(d, 't.asm'), os.path.join(d, 't.bin')
        open(src, 'w').write(PROGRAM)
        subprocess.run(['nasm', '-f', 'bin', '-o', out, src], check=True)
        return open(out, 'rb').read()


# ----- reference model of the modes (heads/SPT are what matter)
def model(mode, c, h, s, lba=True, lba_total=None, user_chs=False):
    """Returns (cylinders, heads, sectors per track) that AH=08h reports
    (as counts), for the drive's P-CHS c/h/s."""
    total = lba_total or c * h * s
    lba_ok = lba and not user_chs
    if mode == NONE:
        return min(c, 1024), h, s
    if mode == LBA_255 and lba_ok and total // (255 * 63) > 0:
        return min(total // (255 * 63), 1024), 255, 63
    if mode == LBA_ASSIST and lba_ok and c > 1024:
        ch = c * h * s // 63
        heads = (ch - 1) // 1024 + 1
        heads = next((x for x in (16, 32, 64, 128) if heads <= x), 255)
        return min(ch // heads, 1024), heads, 63
    # RIVET (v1.1.5) and fallbacks
    while c > 1024:
        c >>= 1
        h <<= 1
    return c, 255 if h == 256 else h, s


def chs_to_lba(cyl, head, sect, heads, spt):
    return (cyl * heads + head) * spt + sect - 1


def addresses(cyls, heads, spt):
    """A spread of CHS addresses within the reported geometry, leaving
    out sector 0 (the test program itself)."""
    pts = {(0, 0, 2), (0, heads - 1, spt), (1, 0, 1), (cyls - 1, heads - 1, spt),
           (cyls // 2, heads // 2, spt // 2 + 1), (cyls - 1, 0, 1)}
    return sorted(p for p in pts if p[0] < cyls and p != (0, 0, 1))


ROMVARS_FLAGS = 0x50
FLG_ROMVARS_MAXSIZE = 0x20


def run_case(rom, mode, geom, lba=True, lba_total=None, maxsize=True):
    c, h, s = geom
    image = bytearray(rom)
    image[xlate_mode_offset(rom)] = mode
    if not maxsize:
        image[ROMVARS_FLAGS] &= ~FLG_ROMVARS_MAXSIZE
    image[-1] = (-sum(image[:-1])) & 0xFF
    lc, lh, ls = model(mode, c, h, s, lba, lba_total)
    if not maxsize and lc > 1:
        lc -= 1             # Diagnostic cylinder reserved (never the only one)
    pts = addresses(lc, lh, ls)
    boot = bytearray(assemble().ljust(512, b'\0'))
    tbl = len(pts).to_bytes(2, 'little')
    for cyl, head, sect in pts:
        cx = ((cyl & 0xFF) << 8) | ((cyl >> 2) & 0xC0) | sect
        tbl += cx.to_bytes(2, 'little') + bytes([0, head])
    boot[TABLE_OFS:TABLE_OFS + len(tbl)] = tbl
    boot[510:512] = b'\x55\xAA'
    drive = xtemu.AtaDrive('RIVET XLATE TEST', c, h, s, lba=lba,
                           lba_total=lba_total, tagged=True)
    drive.write(0, bytes(boot))
    m = xtemu.Machine(bytes(image), [drive, None], False, 1, [], 3000,
                      run_boot_sector=True)
    res = m.boot()
    mem = m.mu.mem_read(RESULTS, 16 + 8 * len(pts))
    w = lambda o: int.from_bytes(mem[o:o + 2], 'little')
    cx, dx = w(0), w(2)
    got = (((cx & 0xC0) << 2 | cx >> 8) + 1, (dx >> 8) + 1, cx & 0x3F)
    reads = []
    for i, (cyl, head, sect) in enumerate(pts):
        o = 16 + 8 * i
        tag = int.from_bytes(mem[o:o + 4], 'little')
        err = w(o + 6) != 0
        reads.append(((cyl, head, sect), tag, err, chs_to_lba(cyl, head, sect, lh, ls)))
    return res, (lc, lh, ls), got, reads


GEOMETRIES = [  # (label, (c, h, s), lba, lba_total)
    ('CF 128MB', (980, 8, 32), True, None),
    ('CF 1GB', (1986, 16, 63), True, None),
    ('odd 2000/4/32', (2000, 4, 32), True, None),
    ('CF 8GB', (15880, 16, 63), True, None),
    ('HDD 20GB', (16383, 16, 63), True, 39070080),
    ('no LBA 2000/16/32', (2000, 16, 32), False, None),
    ('tiny 100/2/17', (100, 2, 17), True, None),
    ('CF 16MB', (490, 2, 32), True, None),      # one 255x63 cylinder
]


def check_rom(path, failures, reference=None, maxsize_variants=(True, False)):
    """Checks every mode on every geometry, with the MAXSIZE option set
    and cleared. With a reference ROM (built before translation modes
    existed), mode 0 must behave identically."""
    rom = open(path, 'rb').read()
    name = os.path.basename(path)
    for maxsize in maxsize_variants:
      for mode in (RIVET, NONE, LBA_ASSIST, LBA_255):
        for label, geom, lba, total in GEOMETRIES:
            what = (f'{name} {MODE_NAMES[mode]} {label}'
                    f'{"" if maxsize else " (no MAXSIZE)"}')
            res, want, got, reads = run_case(rom, mode, geom, lba, total, maxsize)
            if res != ('int18', None):
                failures.append(f'{what}: run ended {res}')
                continue
            # AH=08h reports cylinders - 1 as the maximum (MAXSIZE: none reserved)
            if got != want:
                failures.append(f'{what}: AH=08h {got}, expected {want}')
            for chs, tag, err, lba_want in reads:
                if err or tag != lba_want:
                    failures.append(f'{what}: CHS {chs} read LBA {tag}'
                                    f'{" (error)" if err else ""}, expected {lba_want}')
            if reference and mode == RIVET:
                r = run_case(reference, RIVET, geom, lba, total, maxsize)
                if (r[2], [x[1] for x in r[3]]) != (got, [x[1] for x in reads]):
                    failures.append(f'{what}: differs from reference ROM')


def main(argv):
    args = argv[1:]
    reference = None
    if len(args) >= 2 and args[0] == '--reference':
        reference = open(args[1], 'rb').read()
        args = args[2:]
    roms = args or ['Build/rivet_xt_nomenu.bin']
    failures = []
    for path in roms:
        check_rom(path, failures, reference)
    for f in failures:
        print('FAIL', f)
    print(f'xlate_test: {len(roms)} images, {len(failures)} failures')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
