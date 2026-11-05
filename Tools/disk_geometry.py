#!/usr/bin/env python3
# Rivet: show the CHS geometry a DOS disk was partitioned and formatted with.
# Copyright (C) 2026 Glitch Works, LLC
# Released under the GNU General Public License, version 2 only.
"""Reads (never writes) the MBR partition table and the first sector of
each partition from a disk or disk image, and shows the heads and sectors
per track they were made with. Run it on the whole device (/dev/sdX, not
/dev/sdX1), which usually needs root.

usage: disk_geometry.py DEVICE_OR_IMAGE"""

import sys


def chs(b):
    """Decodes a 3-byte partition table CHS address."""
    head, sect, cyl = b[0], b[1] & 0x3F, b[2] | ((b[1] & 0xC0) << 2)
    return cyl, head, sect


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    with open(argv[1], 'rb') as dev:
        mbr = dev.read(512)
        if mbr[510:512] != b'\x55\xAA':
            sys.exit('No MBR signature (55AA) in sector 0')
        found = []
        print('Partition table (sector 0):')
        for i in range(4):
            e = mbr[446 + 16 * i:446 + 16 * (i + 1)]
            ptype = e[4]
            if ptype == 0:
                continue
            start_lba = int.from_bytes(e[8:12], 'little')
            count = int.from_bytes(e[12:16], 'little')
            s, t = chs(e[1:4]), chs(e[5:8])
            heads, spt = t[1] + 1, t[2]
            print(f'  {i + 1}: type {ptype:02X}h{" (active)" if e[0] == 0x80 else ""}, '
                  f'LBA {start_lba}, {count} sectors ({count * 512 / 2**20:.1f} MiB)')
            print(f'     start CHS {s[0]}/{s[1]}/{s[2]}, end CHS {t[0]}/{t[1]}/{t[2]}'
                  f' -> made with {heads} heads, {spt} sectors per track')
            if spt:
                lba_from_chs = (s[0] * heads + s[1]) * spt + s[2] - 1
                ok = 'matches' if lba_from_chs == start_lba else 'DOES NOT match'
                print(f'     start CHS {ok} the start LBA with that geometry')
            found.append((start_lba, heads, spt))
        for start_lba, heads, spt in found:
            dev.seek(start_lba * 512)
            vbr = dev.read(512)
            bpb_spt = int.from_bytes(vbr[0x18:0x1A], 'little')
            bpb_heads = int.from_bytes(vbr[0x1A:0x1C], 'little')
            hidden = int.from_bytes(vbr[0x1C:0x20], 'little')
            oem = vbr[3:11].decode('ascii', 'replace')
            print(f'Boot sector at LBA {start_lba}: OEM "{oem}", '
                  f'BPB {bpb_heads} heads, {bpb_spt} sectors per track, '
                  f'{hidden} hidden sectors')
            if (bpb_heads, bpb_spt) != (heads, spt):
                print('  Note: BPB and partition table geometry differ')
    print()
    print('Rivet mode to use: whichever gives these heads/sectors for the card.')
    print('  255 heads, 63 sectors  -> 255')
    print('  16/32/64/128 heads, 63 sectors -> assist (or rivet; both give this')
    print('                            for 16-head, 63-sector cards)')
    print('  anything else           -> rivet or none: compare with the card\'s')
    print('                            own geometry (hdparm -I, "default" CHS)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
