#!/usr/bin/env python3
# Rivet: make an RDTEST.CFG from a known-good disk image.
# Copyright (C) 2026 Glitch Works, LLC
# Released under the GNU General Public License, version 2 only.
"""Makes a configuration file for RDTEST.COM (Tools/rdtest) from a disk
image: the sector range to read, and a checksum of each block of it.
Write the image to a card, run RDTEST on the PC under test, and it
reports whether every block reads back as it is in the image.

usage: rdtest_cfg.py IMAGE [-o RDTEST.CFG] [--start N] [--count N]
                     [--block N] [--passes N] [--drive 80] [--no-geometry]

IMAGE can be a raw image or a .gz of one. By default the range is from
LBA 0 up to the last non-zero sector (at most 65535 sectors), so it
covers the partition table, boot sector, FATs, directories and files of
a freshly made disk. The heads and sectors per track the image was made
with are taken from its partition table, so RDTEST can warn if the BIOS
reports a different geometry."""

import argparse
import gzip
import hashlib
import os
import sys

MAX_COUNT = 65535
MAX_BLOCKS = 4096


def checksum(data):
    """RDTEST block checksum: rotate left 1, add each little-endian word."""
    s = 0
    for i in range(0, len(data), 2):
        s = ((s << 1) | (s >> 15)) & 0xFFFF
        s = (s + (data[i] | data[i + 1] << 8)) & 0xFFFF
    return s


def open_image(path):
    return gzip.open(path, 'rb') if path.endswith('.gz') else open(path, 'rb')


def read_sectors(path, start, count):
    with open_image(path) as f:
        f.seek(start * 512)
        data = f.read(count * 512)
    return data.ljust(count * 512, b'\0')


def last_nonzero_sector(path, limit):
    last = -1
    with open_image(path) as f:
        n = 0
        while n < limit:
            chunk = f.read(512 * 2048)
            if not chunk:
                break
            for i in range(0, len(chunk), 512):
                if any(chunk[i:i + 512]):
                    last = n + i // 512
            n += len(chunk) // 512
    return last


def partition_geometry(mbr):
    """Heads/SPT from the first partition entry whose start CHS gives its
    start LBA (the same test Rivet's auto translation mode uses)."""
    if mbr[510:512] != b'\x55\xAA':
        return None
    for i in range(4):
        e = mbr[446 + 16 * i:462 + 16 * i]
        if e[4] == 0:
            continue
        heads, spt = e[5] + 1, e[6] & 0x3F
        if heads > 255 or spt == 0:
            continue
        sh, ss = e[1], e[2] & 0x3F
        sc = e[3] | ((e[2] & 0xC0) << 2)
        if sc >= 1023 or ss == 0 or sh >= heads or ss > spt:
            continue
        if (sc * heads + sh) * spt + ss - 1 == int.from_bytes(e[8:12], 'little'):
            return heads, spt
    return None


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('image')
    ap.add_argument('-o', '--output', default='RDTEST.CFG')
    ap.add_argument('--start', type=int, default=0)
    ap.add_argument('--count', type=int)
    ap.add_argument('--block', type=int, default=64)
    ap.add_argument('--passes', type=int, default=3)
    ap.add_argument('--drive', default='80', help='BIOS drive number, hex')
    ap.add_argument('--no-geometry', action='store_true')
    a = ap.parse_args(argv[1:])

    count = a.count
    if count is None:
        last = last_nonzero_sector(a.image, a.start + MAX_COUNT)
        if last < a.start:
            sys.exit('No data in the image from the start LBA on')
        count = min(last - a.start + 1, MAX_COUNT)
        count = min(-(-count // a.block) * a.block, MAX_COUNT)
    if not 1 <= count <= MAX_COUNT:
        sys.exit(f'--count must be 1...{MAX_COUNT}')
    if not 1 <= a.block <= MAX_COUNT or -(-count // a.block) > MAX_BLOCKS:
        sys.exit(f'--block too small: at most {MAX_BLOCKS} blocks')
    if not 1 <= a.passes <= 255:
        sys.exit('--passes must be 1...255')

    data = read_sectors(a.image, a.start, count)
    sums = [checksum(data[b * 512 * a.block:min((b + 1) * a.block, count) * 512])
            for b in range(-(-count // a.block))]
    geometry = None if a.no_geometry else partition_geometry(read_sectors(a.image, 0, 1))

    h = hashlib.sha256()
    with open_image(a.image) as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)

    lines = [f'; RDTEST.CFG made by rdtest_cfg.py from {os.path.basename(a.image)}',
             f'; image SHA-256 (uncompressed): {h.hexdigest()}',
             f'DRIVE={int(a.drive, 16):02X}',
             f'START={a.start}',
             f'COUNT={count}',
             f'BLOCK={a.block}',
             f'PASSES={a.passes}']
    if geometry:
        lines += [f'HEADS={geometry[0]}', f'SPT={geometry[1]}']
    for i in range(0, len(sums), 8):
        lines.append('SUM=' + ' '.join(f'{v:04X}' for v in sums[i:i + 8]))
    open(a.output, 'w', newline='\r\n').write('\n'.join(lines) + '\n')
    print(f'{a.output}: LBA {a.start}-{a.start + count - 1}, {len(sums)} blocks of '
          f'{a.block}, {a.passes} passes'
          + (f', made at {geometry[0]}/{geometry[1]}' if geometry else ', no geometry'))
    return 0


if __name__ == '__main__':
    sys.exit(main(argv=sys.argv))
