#!/usr/bin/env python3
# Rivet: set a drive's CHS translation mode in a ROM image.
# Copyright (C) 2026 Glitch Works, LLC
# Released under the GNU General Public License, version 2 only.
"""Sets the CHS translation mode for one drive in a Rivet ROM image and
fixes the checksum. A stopgap until the configuration program exists.

usage: set_xlate.py IMAGE CONTROLLER DRIVE MODE [-o OUTPUT]

  CONTROLLER  0...4, in the order the image lists them (XT images: 0 is
              the XT-IDE at 300h; AT images: 0 = 1F0h, 1 = 170h, 2 = 300h)
  DRIVE       master or slave
  MODE        rivet  (0) v1.1.5 bit shift, the default
              none   (1) no translation, at most 1024 cylinders
              assist (2) LBA assist above 1024 cylinders (XUB 2.x)
              255    (3) always 255 heads, 63 sectors (later PCs)

Without -o the image is changed in place."""

import argparse
import sys

SIGNATURE = b'RIVET010'
ROMVARS_SIGN = 0x10
ROMVARS_IDE_CNT = 0x52
ROMVARS_IDEVARS0 = 0x60
IDEVARS_SIZE = 26
DRVPARAMS = {'master': 10, 'slave': 18}
DRVPARAMS_XLATE_MODE = 2
MODES = {'rivet': 0, 'none': 1, 'assist': 2, '255': 3}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('image')
    ap.add_argument('controller', type=int, choices=range(5))
    ap.add_argument('drive', choices=DRVPARAMS)
    ap.add_argument('mode', choices=MODES)
    ap.add_argument('-o', '--output')
    a = ap.parse_args(argv[1:])

    image = bytearray(open(a.image, 'rb').read())
    if image[:2] != b'\x55\xAA' or image[ROMVARS_SIGN:ROMVARS_SIGN + 8] != SIGNATURE:
        sys.exit(f'{a.image}: not a Rivet ({SIGNATURE.decode()}) image')
    if a.controller >= image[ROMVARS_IDE_CNT]:
        sys.exit(f'{a.image}: only {image[ROMVARS_IDE_CNT]} controller(s) configured')
    ide = ROMVARS_IDEVARS0 + a.controller * IDEVARS_SIZE
    port = int.from_bytes(image[ide:ide + 2], 'little')
    image[ide + DRVPARAMS[a.drive] + DRVPARAMS_XLATE_MODE] = MODES[a.mode]
    image[-1] = 0
    image[-1] = (-sum(image)) & 0xFF
    open(a.output or a.image, 'wb').write(image)
    print(f'{a.output or a.image}: controller {a.controller} ({port:03X}h) '
          f'{a.drive}: translation mode {a.mode}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
