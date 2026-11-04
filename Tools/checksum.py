#!/usr/bin/env python3
"""Set the option ROM checksum byte of a BIOS image, in place.

A PC option ROM is valid when all of its bytes sum to zero (mod 256). This
tool rewrites the last byte of the image so that holds.

It also checks the image's size against the size byte in the ROM header
(offset 2, in 512-byte blocks). If the two disagree, it fails without
writing anything.

Copyright (C) 2026 Glitch Works, LLC

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License version 2 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.
"""

import sys


def main(argv):
    if len(argv) != 2:
        print("usage: checksum.py IMAGE", file=sys.stderr)
        return 2

    path = argv[1]
    with open(path, "rb") as f:
        image = bytearray(f.read())

    if len(image) < 3 or image[0:2] != b"\x55\xaa":
        print(f"{path}: no 55AAh option ROM signature", file=sys.stderr)
        return 1

    header_size = image[2] * 512
    if header_size != len(image):
        print(
            f"{path}: image is {len(image)} bytes but header says "
            f"{header_size}",
            file=sys.stderr,
        )
        return 1

    image[-1] = (-sum(image[:-1])) & 0xFF

    with open(path, "wb") as f:
        f.write(image)

    print(f"{path}: checksum byte set to {image[-1]:02X}h")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
