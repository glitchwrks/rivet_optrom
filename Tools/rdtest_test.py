#!/usr/bin/env python3
# Rivet: tests for RDTEST.COM and rdtest_cfg.py on the emulated XT.
# Copyright (C) 2026 Glitch Works, LLC
# Released under the GNU General Public License, version 2 only.
"""Builds RDTEST.COM and RDMKCFG.COM, and runs them under a minimal DOS
(the INT 21h functions they use) on the emulated XT with a Rivet image.

RDTEST: checked against configurations from rdtest_cfg.py made from a
synthetic disk image: a clean disk, corrupted sectors, a geometry
mismatch warning, a range that crosses cylinders, a missing or bad
configuration file.

RDMKCFG: its configuration must hold the same values as rdtest_cfg.py's
for the same disk (default range and switches), must pass RDTEST on the
same disk, and a read error must leave no file."""

import os
import random
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xtemu  # noqa: E402
import xlate_test  # noqa: E402
from unicorn.x86_const import (UC_X86_REG_AX, UC_X86_REG_BX, UC_X86_REG_CS,  # noqa: E402
                               UC_X86_REG_CX, UC_X86_REG_DL, UC_X86_REG_DS,
                               UC_X86_REG_DX, UC_X86_REG_ES, UC_X86_REG_IP,
                               UC_X86_REG_SP, UC_X86_REG_SS, UC_X86_REG_AL)

PSP = 0x1000                     # Segment the .COM runs in


class DosMachine(xtemu.Machine):
    """Just enough DOS for RDTEST.COM and RDMKCFG.COM."""
    files = {}

    def _name_at_dsdx(self):
        a, name = self.r(UC_X86_REG_DS) * 16 + self.r(UC_X86_REG_DX), b''
        while self.mu.mem_read(a, 1) != b'\0':
            name += bytes(self.mu.mem_read(a, 1))
            a += 1
        return name.decode().upper()

    def _int21(self):
        ah = self.r(UC_X86_REG_AX) >> 8
        ds = self.r(UC_X86_REG_DS)
        if ah == 0x02:
            self.screen.teletype(self.r(UC_X86_REG_DL))
        elif ah == 0x3C:
            self._writing = self._name_at_dsdx()
            self.files[self._writing] = b''
            self.w(UC_X86_REG_AX, 6)
            self._ret_cf(False)
        elif ah == 0x40:
            n = self.r(UC_X86_REG_CX)
            self.files[self._writing] += bytes(
                self.mu.mem_read(ds * 16 + self.r(UC_X86_REG_DX), n))
            self.w(UC_X86_REG_AX, n)
            self._ret_cf(False)
        elif ah == 0x3D:
            data = self.files.get(self._name_at_dsdx())
            if data is None:
                self.w(UC_X86_REG_AX, 2)
                self._ret_cf(True)
            else:
                self._open, self._pos = data, 0
                self.w(UC_X86_REG_AX, 5)
                self._ret_cf(False)
        elif ah == 0x3F:
            n = self.r(UC_X86_REG_CX)
            chunk = self._open[self._pos:self._pos + n]
            self._pos += len(chunk)
            self.mu.mem_write(ds * 16 + self.r(UC_X86_REG_DX), chunk)
            self.w(UC_X86_REG_AX, len(chunk))
            self._ret_cf(False)
        elif ah == 0x3E:
            self._ret_cf(False)
        elif ah == 0x4C:
            self.result = ('exit', self.r(UC_X86_REG_AL))
            self.mu.emu_stop()


def build_com(tmp, name='rdtest'):
    out = os.path.join(tmp, name.upper() + '.COM')
    subprocess.run(['nasm', '-f', 'bin', '-I' + os.path.join(HERE, 'rdtest') + os.sep,
                    '-o', out, os.path.join(HERE, 'rdtest', name + '.asm')], check=True)
    return open(out, 'rb').read()


def make_image(tmp, nsect=40000, data_until=None):
    """A 16383/16/63 drive image: an MBR with a 255/63 partition, then
    pseudo-random data (up to data_until, zeros after that)."""
    rnd = random.Random(5150)
    data_until = data_until or nsect
    sectors = [bytes(rnd.getrandbits(8) for _ in range(512)) if n < data_until
               else bytes(512) for n in range(nsect)]
    mbr = bytearray(512)
    mbr[446:462] = xlate_test.part_entry(255, 63)
    mbr[510:512] = b'\x55\xAA'
    sectors[0] = bytes(mbr)
    path = os.path.join(tmp, 'test.img')
    open(path, 'wb').write(b''.join(sectors))
    return path, sectors


def make_cfg(image, tmp, *args):
    out = os.path.join(tmp, 'RDTEST.CFG')
    subprocess.run([sys.executable, os.path.join(HERE, 'rdtest_cfg.py'), image,
                    '-o', out, *args], check=True, stdout=subprocess.DEVNULL)
    return open(out, 'rb').read()


def run_com(rom_path, com, sectors, files, cmdline='', corrupt=(), mode=0,
            bad=(), keys=()):
    rom = bytearray(open(rom_path, 'rb').read())
    rom[xlate_test.xlate_mode_offset(rom)] = mode
    rom[-1] = 0
    rom[-1] = (-sum(rom)) & 0xFF
    drive = xtemu.AtaDrive('RDTEST DRIVE', 16383, 16, 63, lba_total=30146256)
    for n, s in enumerate(sectors):
        if n in corrupt:
            s = bytes([s[0] ^ 0x80]) + s[1:]
        drive.write(n, s)
    drive.bad = set(bad)
    m = DosMachine(bytes(rom), [drive, None], False, 1, [], 60000)
    m.keys.extend(keys)             # Pressed while the .COM runs
    m.files = files
    res = m.boot()
    assert res == ('boot', 0x80), res
    m.run_boot_sector = True
    base = PSP * 16
    tail = (' ' + cmdline).encode() if cmdline else b''
    m.mu.mem_write(base + 0x80, bytes([len(tail)]) + tail + b'\r')
    m.mu.mem_write(base + 0x100, com)
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        m.w(reg, PSP)
    m.w(UC_X86_REG_SP, 0xFFFE)
    m.w(UC_X86_REG_IP, 0x100)
    m.result = None
    res = m._run()
    text = m.screen.text()
    for title in ('RDTEST disk', 'RDMKCFG'):
        if title in text:
            return res, text[text.find(title):]
    return res, text


def cfg_values(text):
    """Configuration lines without comments, for comparing generators."""
    lines = text.decode().replace('\r', '').split('\n')
    return [ln for ln in lines if ln and not ln.startswith(';')]


def main(argv):
    rom = argv[1] if len(argv) > 1 else os.path.join('Build', 'rivet_xt_nomenu.bin')
    failures = []

    def check(name, cond, detail):
        if not cond:
            failures.append(f'{name}: {detail}')

    with tempfile.TemporaryDirectory() as tmp:
        com = build_com(tmp)
        image, sectors = make_image(tmp)

        cfg = make_cfg(image, tmp, '--count', '2048')
        res, out = run_com(rom, com, sectors, {'RDTEST.CFG': cfg})
        check('clean', res == ('exit', 0) and 'All passes match' in out, (res, out))

        res, out = run_com(rom, com, sectors, {'RDTEST.CFG': cfg}, corrupt={700, 1500})
        check('corrupt', res == ('exit', 1) and out.count('2 block(s) bad') == 3
              and 'FAILED' in out, (res, out))

        # Configuration named on the command line
        res, out = run_com(rom, com, sectors, {'CARD.CFG': cfg}, cmdline='card.cfg')
        check('named config', res == ('exit', 0), (res, out))

        res, out = run_com(rom, com, sectors, {})
        check('missing config', res == ('exit', 3) and 'Cannot open' in out, (res, out))

        # The image was made at 255/63; rivet mode on a 16383/16/63 drive
        # also gives 255 heads, mode none gives 16
        res, out = run_com(rom, com, sectors, {'RDTEST.CFG': cfg}, mode=xlate_test.NONE)
        check('geometry warning', res == ('exit', 0) and 'WARNING' in out, (res, out))
        res, out = run_com(rom, com, sectors, {'RDTEST.CFG': cfg})
        check('no geometry warning', 'WARNING' not in out, out)

        # A range across cylinder boundaries (16065 sectors per cylinder)
        cfg2 = make_cfg(image, tmp, '--start', '31900', '--count', '640', '--block', '32')
        res, out = run_com(rom, com, sectors, {'RDTEST.CFG': cfg2}, corrupt={32130})
        check('cylinder crossing', res == ('exit', 1) and '.......X....' in out, (res, out))

        # CTRL+C and CTRL+BREAK abort; other keys are ignored. Keys are
        # queued before the program starts, so the first check sees them.
        for key in ('ctrlc', 'ctrlbreak'):
            res, out = run_com(rom, com, sectors, {'RDTEST.CFG': cfg}, keys=[(0, key)])
            check(f'{key} aborts', res == ('exit', 4) and 'Aborted' in out
                  and 'Press CTRL+C to abort' in out, (res, out))
        res, out = run_com(rom, com, sectors, {'RDTEST.CFG': cfg}, keys=[(0, 'd')])
        check('other key ignored', res == ('exit', 0) and 'All passes match' in out,
              (res, out))

        bad = cfg.replace(b'COUNT=2048', b'COUNT=1900')   # 30 blocks, 32 SUMs
        res, out = run_com(rom, com, sectors, {'RDTEST.CFG': bad})
        check('sum count check', res == ('exit', 2) and 'number of SUM' in out, (res, out))

        # ----- RDMKCFG
        mk = build_com(tmp, 'rdmkcfg')
        image2, sectors2 = make_image(tmp, nsect=4000, data_until=3000)
        files = {}
        res, out = run_com(rom, mk, sectors2, files)
        made = files.get('RDTEST.CFG', b'')
        want = make_cfg(image2, tmp)
        check('rdmkcfg default', res == ('exit', 0) and
              cfg_values(made) == cfg_values(want), (res, out, made[:300], want[:300]))
        res, out = run_com(rom, com, sectors2, {'RDTEST.CFG': made})
        check('rdmkcfg config passes rdtest', res == ('exit', 0), (res, out))

        files = {}
        res, out = run_com(rom, mk, sectors2, files,
                           cmdline='/s:100 /C:1000 /b:32 /p:2 TEST.CFG')
        want = make_cfg(image2, tmp, '--start', '100', '--count', '1000',
                        '--block', '32', '--passes', '2')
        check('rdmkcfg switches', res == ('exit', 0) and
              cfg_values(files.get('TEST.CFG', b'')) == cfg_values(want),
              (res, out, files.get('TEST.CFG', b'')[:300]))

        files = {}
        res, out = run_com(rom, mk, sectors2, files, bad={1500})
        check('rdmkcfg read error', res == ('exit', 1) and not files, (res, out))

        files = {}
        res, out = run_com(rom, mk, sectors2, files, keys=[(0, 'ctrlc')])
        check('rdmkcfg ctrlc', res == ('exit', 4) and not files, (res, out))

        res, out = run_com(rom, mk, sectors2, {}, cmdline='/x')
        check('rdmkcfg bad switch', res == ('exit', 2) and 'usage' in out, (res, out))

    for f in failures:
        print('FAIL', f)
    print(f'rdtest_test: {len(failures)} failures')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
