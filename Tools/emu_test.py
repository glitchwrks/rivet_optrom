#!/usr/bin/env python3
"""Behaviour tests for Rivet ROM images, run on the xtemu harness.

Needs Unicorn (pip install unicorn). Usage:

    python3 Tools/emu_test.py Build/

Prints only failures, plus a one-line summary. Exits non-zero on failure.

Copyright (C) 2026 Glitch Works, LLC

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License version 2 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xtemu  # noqa: E402

FAILURES = []


def check(name, cond, detail=''):
    if not cond:
        FAILURES.append(f'{name}: {detail}')


ROMVARS_BOOT_DELAY = 0x55     # Boot Menu selection delay (seconds)
ROMVARS_BOOT_LDR_TYPE = 0x56  # Boot loader type
ROMVARS_BUILD_FLAGS = 0x59    # wBuildFlags (read only build description)
FLG_BUILD_NOBOOTMENU = 0x01
BOOTLOADER_TYPE_MENU = 0
BOOTLOADER_TYPE_NONE = 6


def patched(rom, offset, value):
    """Return a copy of a ROM image with one ROMVARS byte changed."""
    image = bytearray(open(rom, 'rb').read())
    image[offset] = value
    image[-1] = (-sum(image[:-1])) & 0xFF
    return bytes(image)


def run(rom, hispeed=False, drives=1, floppies=1, keys=(), max_ticks=300,
        cursor_shape=None, floppy_bootable=False, boot_sector=True):
    d = xtemu.make_drives(drives) + [None] * (2 - drives)
    if not boot_sector:
        d[0].write(0, bytes(512))
    image = rom if isinstance(rom, bytes) else open(rom, 'rb').read()
    m = xtemu.Machine(image, d, hispeed, floppies, list(keys), max_ticks,
                      floppy_bootable=floppy_bootable)
    if cursor_shape is not None:
        m.screen.cursor_shape = cursor_shape
    return m, m.boot()


def build_flags(path):
    image = open(path, 'rb').read()
    return image[ROMVARS_BUILD_FLAGS] | image[ROMVARS_BUILD_FLAGS + 1] << 8


def test_image(path, hispeed):
    name = os.path.basename(path)
    check(f'{name} build flags', build_flags(path) == 0, build_flags(path))

    # Boots the default (first hard disk) with Enter
    m, res = run(path, hispeed, keys=[(40, 'enter')])
    check(f'{name} enter boots 80h', res == ('boot', 0x80), res)

    # Menu is drawn and idles without redrawing constantly
    m, res = run(path, hispeed, keys=[], max_ticks=80)
    prof = xtemu.menu_profile(m)
    check(f'{name} menu reached', prof is not None, res)
    if prof:
        check(f'{name} idle redraw', prof['idle_per_second'] < 20, prof)
    check(f'{name} drive listed', 'RIVET TEST DISK 0' in m.screen.text(),
          m.screen.text())
    check(f'{name} title shown', 'Rivet Option ROM' in m.screen.text(),
          m.screen.text())

    # Navigation: up to the floppy, down back to the hard disk, boot it
    m, res = run(path, hispeed, keys=[(40, 'up'), (42, 'down'), (44, 'enter')])
    check(f'{name} navigate and boot', res == ('boot', 0x80), res)

    # Hotkey for the second hard disk boots it as 80h (translated)
    m, res = run(path, hispeed, drives=2, keys=[(40, 'd')])
    check(f'{name} hotkey D', res == ('boot', 0x80), res)

    # Timeout boots the default (delay shortened to 2 s to keep this quick)
    m, res = run(patched(path, ROMVARS_BOOT_DELAY, 2), hispeed, keys=[],
                 max_ticks=200)
    check(f'{name} timeout boots', res == ('boot', 0x80), res)

    # Cursor shape set by the video BIOS survives the menu (MDA uses
    # scan lines 0Bh-0Ch; restoring a fixed CGA 0607h centres it)
    for shape in (0x0B0C, 0x0607):
        m, res = run(path, hispeed, keys=[(40, 'esc'), (60, 'enter')],
                     cursor_shape=shape)
        check(f'{name} cursor shape {shape:04X}',
              res == ('boot', 0x80) and m.screen.cursor_shape == shape,
              (res, hex(m.screen.cursor_shape)))

    # Image on a board jumpered for the other mode finds no drives
    m, res = run(path, not hispeed, keys=[], max_ticks=400)
    check(f'{name} mismatched board', 'RIVET TEST DISK 0' not in m.screen.text(),
          m.screen.text())


def test_nomenu_image(path, hispeed):
    """Images built without the Boot Menu boot in BIOS order."""
    name = os.path.basename(path)
    check(f'{name} build flags', build_flags(path) == FLG_BUILD_NOBOOTMENU,
          build_flags(path))

    # No disk in A:, so it boots C: without waiting for anything, and only
    # teletype output is used (no menu drawing)
    m, res = run(path, hispeed, keys=[], max_ticks=100)
    check(f'{name} boots 80h', res == ('boot', 0x80), res)
    check(f'{name} teletype only', set(m.int10) <= {0x0E}, dict(m.int10))
    check(f'{name} no menu', 'Selection Timeout' not in m.screen.text(),
          m.screen.text())
    check(f'{name} silent boot', 'Booting from' not in m.screen.text()
          and "Can't boot" not in m.screen.text(), m.screen.text())

    # A hard disk without a boot sector is reported before INT 18h
    m, res = run(path, hispeed, keys=[], max_ticks=100, boot_sector=False)
    check(f'{name} no boot sector', res == ('int18', None) and
          "Can't boot hard disk 80h: no boot sector" in m.screen.text(),
          (res, m.screen.text()))

    # A bootable disk in A: is booted first
    m, res = run(path, hispeed, keys=[], max_ticks=100, floppy_bootable=True)
    check(f'{name} boots A:', res == ('boot', 0x00), res)

    # Boot loader types the image can't provide fall back to the simple one
    for ldr in (BOOTLOADER_TYPE_MENU, BOOTLOADER_TYPE_NONE):
        m, res = run(patched(path, ROMVARS_BOOT_LDR_TYPE, ldr), hispeed,
                     keys=[], max_ticks=100)
        check(f'{name} loader type {ldr}', res == ('boot', 0x80), res)


def main(argv):
    build = argv[1] if len(argv) > 1 else 'Build'
    images = [('rivet_xt.bin', False), ('rivet_xtp.bin', False),
              ('rivet_xt_hs.bin', True), ('rivet_xtp_hs.bin', True)]
    for img, hs in images:
        test_image(os.path.join(build, img), hs)
        test_nomenu_image(os.path.join(build, img[:-4] + '_nomenu.bin'), hs)
    for f in FAILURES:
        print('FAIL', f)
    print(f'emu_test: {2 * len(images)} images, {len(FAILURES)} failures')
    return 1 if FAILURES else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
