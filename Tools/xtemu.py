#!/usr/bin/env python3
"""xtemu: run a Rivet option ROM image on an emulated PC/XT.

This is a test harness, not a PC emulator. The CPU is emulated with Unicorn
(pip install unicorn). Everything else is a thin model, just enough to
exercise the ROM:

* BIOS services (INT 10h, 11h, 12h, 13h floppy, 15h, 16h, 1Ah) are
  implemented in Python. INT 10h output goes to an 80x25 text buffer and
  every call is counted by function, so screen output and BIOS call counts
  can be compared between ROM builds.
* An XT-IDE board at 300h with ATA drives, in NORMAL or HI-SPEED (A0/A3
  swapped) layout.
* Time: the BIOS tick count advances every INSNS_PER_TICK instructions,
  roughly an 8088 at 4.77 MHz. It is only used to drive timeouts, not to
  measure speed.

The ROM is started the way a real BIOS would: a far call to its ROM-scan
entry point (offset 3), then INT 19h. A run ends when the ROM jumps to a
boot sector (0000:7C00), calls the system's INT 18h, waits for a key when
the key script is empty, or runs out of its tick budget.

Copyright (C) 2026 Glitch Works, LLC

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License version 2 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.
"""

import argparse
import collections
import sys

from unicorn import Uc, UcError, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, \
    UC_HOOK_INSN, UC_HOOK_CODE
from unicorn.x86_const import *

ROM_SEGMENT = 0xC800
STUB_SEGMENT = 0xF000
STUB_BASE = 0x0100          # stub for vector n at F000:0100+n
SENTINEL_OFS = 0x0010       # far-return target after ROM init
INSNS_PER_TICK = 20000

# Keyboard: (scan << 8) | ascii
KEYS = {
    'up': 0x4800, 'down': 0x5000, 'home': 0x4700, 'end': 0x4F00,
    'pgup': 0x4900, 'pgdn': 0x5100, 'enter': 0x1C0D, 'esc': 0x011B,
    'left': 0x4B00, 'right': 0x4D00,
}
for c in 'abcdefghijklmnopqrstuvwxyz':
    KEYS[c] = ord(c)

FLAG_CF, FLAG_ZF, FLAG_IF = 0x0001, 0x0040, 0x0200

CP437_LOW = (' ☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼')


class Screen:
    def __init__(self, cols=80, rows=25):
        self.cols, self.rows = cols, rows
        self.chars = [[0x20] * cols for _ in range(rows)]
        self.attrs = [[0x07] * cols for _ in range(rows)]
        self.row = self.col = 0
        self.cursor_shape = 0x0607

    def clear(self):
        for r in range(self.rows):
            self.chars[r] = [0x20] * self.cols
            self.attrs[r] = [0x07] * self.cols
        self.row = self.col = 0

    def _scroll_up(self):
        self.chars.pop(0)
        self.attrs.pop(0)
        self.chars.append([0x20] * self.cols)
        self.attrs.append([0x07] * self.cols)

    def teletype(self, ch):
        if ch == 0x0D:
            self.col = 0
        elif ch == 0x0A:
            self.row += 1
        elif ch == 0x08:
            self.col = max(0, self.col - 1)
        elif ch == 0x07:
            pass
        else:
            self.chars[self.row][self.col] = ch
            self.col += 1
            if self.col >= self.cols:
                self.col = 0
                self.row += 1
        if self.row >= self.rows:
            self._scroll_up()
            self.row = self.rows - 1

    def write_repeat(self, ch, attr, count):
        r, c = self.row, self.col
        for _ in range(count):
            if r >= self.rows:
                break
            self.chars[r][c] = ch
            if attr is not None:
                self.attrs[r][c] = attr
            c += 1
            if c >= self.cols:
                c = 0
                r += 1

    def text(self):
        # CP437 rendered as Unicode for readability, including the glyphs
        # for control-code positions (e.g. 1Ah is the right arrow).
        return '\n'.join(''.join(CP437_LOW[c] if c < 0x20 else
                                  bytes([c]).decode('cp437') for c in row).rstrip()
                         for row in self.chars)


class AtaDrive:
    def __init__(self, model, cyls, heads, spt, lba=True, lba_total=None,
                 tagged=False):
        self.model, self.cyls, self.heads, self.spt = model, cyls, heads, spt
        self.total = cyls * heads * spt
        self.lba, self.lba_total = lba, lba_total or self.total
        self.tagged = tagged    # unwritten sectors start with their LBA
        self.sectors = {}       # lba -> bytes(512), sparse
        self.multiple = 0

    def identify(self):
        w = [0] * 256
        w[0] = 0x0040
        w[1], w[3], w[6] = self.cyls, self.heads, self.spt
        w[47] = 0x8010
        w[49] = 0x0200 if self.lba else 0   # LBA supported
        w[53] = 0x0001
        w[54], w[55], w[56] = self.cyls, self.heads, self.spt
        w[57], w[58] = self.total & 0xFFFF, self.total >> 16
        w[59] = 0x0100 | self.multiple if self.multiple else 0
        if self.lba:
            n = min(self.lba_total, 0x0FFFFFFF)
            w[60], w[61] = n & 0xFFFF, n >> 16

        def put_str(start, nwords, s):
            s = s.ljust(nwords * 2)[:nwords * 2].encode('ascii')
            for i in range(nwords):
                w[start + i] = (s[2 * i] << 8) | s[2 * i + 1]
        put_str(10, 10, 'RIVETEMU0001')
        put_str(23, 4, '1.0')
        put_str(27, 20, self.model)
        return b''.join(x.to_bytes(2, 'little') for x in w)

    def read(self, lba):
        if lba in self.sectors:
            return self.sectors[lba]
        if self.tagged:
            return (lba.to_bytes(4, 'little') + b'LBA!').ljust(512, b'\0')
        return bytes(512)

    def write(self, lba, data):
        self.sectors[lba] = bytes(data)


class XtIde:
    """XT-IDE at a 16-port window. Data high byte latched at offset 8
    (NORMAL) or 1 (HI-SPEED, A0 and A3 swapped)."""

    ERR, DRQ, DSC, DRDY, BSY = 0x01, 0x08, 0x10, 0x40, 0x80

    def __init__(self, base, drives, hispeed=False):
        self.base, self.hispeed = base, hispeed
        self.drives = drives        # [master, slave], entries may be None
        self.regs = {1: 0, 2: 1, 3: 1, 4: 0, 5: 0, 6: 0xA0}
        self.status = self.DRDY | self.DSC
        self.error = 0
        self.buf = b''
        self.bufpos = 0
        self.latch = 0
        self.after_buffer = None    # callable when a write buffer fills
        self.srst = False
        self.log = []

    def owns(self, port):
        return self.base <= port < self.base + 16

    def _offset(self, port):
        off = port - self.base
        if self.hispeed and (off & 1) != ((off >> 3) & 1):
            off ^= 9
        return off

    def _drive(self):
        return self.drives[(self.regs[6] >> 4) & 1]

    def _status(self):
        if self._drive() is None:
            return 0x00
        return self.status

    def _lba(self):
        r = self.regs
        if r[6] & 0x40:
            return ((r[6] & 0x0F) << 24) | (r[5] << 16) | (r[4] << 8) | r[3]
        d = self._drive()
        cyl = (r[5] << 8) | r[4]
        return (cyl * d.heads + (r[6] & 0x0F)) * d.spt + (r[3] - 1)

    def _count(self):
        return self.regs[2] or 256

    # ----- data register
    def _next_data_word(self):
        if not (self.status & self.DRQ) or self.after_buffer:
            return 0xFFFF
        word = self.buf[self.bufpos] | (self.buf[self.bufpos + 1] << 8)
        self.bufpos += 2
        if self.bufpos >= len(self.buf):
            self._read_buffer_done()
        return word

    def _read_buffer_done(self):
        self.remaining -= self.chunk
        if self.remaining > 0:
            self._load_read_chunk()
        else:
            self.status = self.DRDY | self.DSC

    def _load_read_chunk(self):
        d = self._drive()
        self.chunk = min(self.per_drq, self.remaining)
        self.buf = b''.join(d.read(self.lba + i) for i in range(self.chunk))
        self.lba += self.chunk
        self.bufpos = 0
        self.status = self.DRDY | self.DSC | self.DRQ

    def _put_data_word(self, word):
        if not (self.status & self.DRQ) or not self.after_buffer:
            return
        self.wbuf.append(word & 0xFF)
        self.wbuf.append(word >> 8)
        if len(self.wbuf) >= 512 * self.chunk:
            self.after_buffer()

    def _write_buffer_done(self):
        d = self._drive()
        for i in range(self.chunk):
            d.write(self.lba + i, self.wbuf[512 * i:512 * (i + 1)])
        self.lba += self.chunk
        self.remaining -= self.chunk
        self.wbuf = bytearray()
        if self.remaining > 0:
            self.chunk = min(self.per_drq, self.remaining)
            self.status = self.DRDY | self.DSC | self.DRQ
        else:
            self.after_buffer = None
            self.status = self.DRDY | self.DSC

    # ----- commands
    def _command(self, cmd):
        self.log.append(cmd)
        d = self._drive()
        self.error = 0
        self.after_buffer = None
        if d is None:
            return
        if cmd == 0xEC:
            self.buf, self.bufpos = d.identify(), 0
            self.remaining = self.chunk = self.per_drq = 1
            self.status = self.DRDY | self.DSC | self.DRQ
        elif cmd in (0x20, 0x21, 0xC4):
            self.lba, self.remaining = self._lba(), self._count()
            self.per_drq = d.multiple if (cmd == 0xC4 and d.multiple) else 1
            self._load_read_chunk()
        elif cmd in (0x30, 0x31, 0xC5):
            self.lba, self.remaining = self._lba(), self._count()
            self.per_drq = d.multiple if (cmd == 0xC5 and d.multiple) else 1
            self.chunk = min(self.per_drq, self.remaining)
            self.wbuf = bytearray()
            self.after_buffer = self._write_buffer_done
            self.status = self.DRDY | self.DSC | self.DRQ
        elif cmd == 0xC6:
            d.multiple = self.regs[2]
            self.status = self.DRDY | self.DSC
        elif cmd in (0x91, 0xEF, 0x10, 0x40, 0x41, 0x70, 0x90):
            self.status = self.DRDY | self.DSC
        else:
            self.error = 0x04
            self.status = self.DRDY | self.DSC | self.ERR

    # ----- port interface
    def read(self, port):
        off = self._offset(port)
        if off == 0:
            word = self._next_data_word()
            self.latch = word >> 8
            return word & 0xFF
        if off == 8:
            return self.latch
        if off == 1:
            return self.error
        if off in (7, 0x0E):
            return self._status()
        return self.regs.get(off, 0xFF)

    def write(self, port, value):
        off = self._offset(port)
        if off == 0:
            self._put_data_word((self.latch << 8) | value)
        elif off == 8:
            self.latch = value
        elif off == 7:
            self._command(value)
        elif off == 0x0E:
            srst = bool(value & 0x04)
            if self.srst and not srst:
                self.status = self.DRDY | self.DSC
            self.srst = srst
        elif 1 <= off <= 6:
            self.regs[off] = value


class Machine:
    def __init__(self, rom, drives, hispeed=False, floppies=0,
                 keys=(), max_ticks=600, trace_int10=False,
                 floppy_bootable=False, run_boot_sector=False):
        self.mu = Uc(UC_ARCH_X86, UC_MODE_16)
        self.mu.mem_map(0, 0x100000)
        self.mem_rom = rom
        self.mu.mem_write(ROM_SEGMENT * 16, rom)
        self.screen = Screen()
        self.ide = XtIde(0x300, drives, hispeed)
        self.floppies = floppies
        self.floppy_bootable = floppy_bootable  # disk in A: with a boot sector
        self.run_boot_sector = run_boot_sector  # keep going at 0:7C00
        self.keys = collections.deque(keys)     # (tick, keyword)
        self.max_ticks = max_ticks
        self.int10 = collections.Counter()
        self.int10_log = []                     # (tick, ah)
        self.polls = []                         # ticks of INT 16h AH=01h
        self.key_costs = []                     # INT 10h calls per key
        self._key_mark = None
        self.trace_int10 = trace_int10
        self.events = []
        self.result = None
        self.stop = False
        self.pic = {0x21: 0, 0xA1: 0}
        self._setup_memory()
        mu = self.mu
        mu.hook_add(UC_HOOK_INTR, self._on_int)
        mu.hook_add(UC_HOOK_INSN, self._on_in, None, 1, 0, UC_X86_INS_IN)
        mu.hook_add(UC_HOOK_INSN, self._on_out, None, 1, 0, UC_X86_INS_OUT)
        stub = STUB_SEGMENT * 16
        mu.hook_add(UC_HOOK_CODE, self._on_stub, None,
                    stub + STUB_BASE, stub + STUB_BASE + 0xFF)
        mu.hook_add(UC_HOOK_CODE, self._on_sentinel, None,
                    stub + SENTINEL_OFS, stub + SENTINEL_OFS)
        mu.hook_add(UC_HOOK_CODE, self._on_boot, None, 0x7C00, 0x7C00)

    # ----- memory and BIOS data area
    def _setup_memory(self):
        mu = self.mu
        stub = STUB_SEGMENT * 16
        mu.mem_write(stub + STUB_BASE, b'\xCF' * 256)   # IRET per vector
        mu.mem_write(stub + SENTINEL_OFS, b'\xF4')       # HLT
        ivt = b''.join((STUB_BASE + n).to_bytes(2, 'little') +
                       STUB_SEGMENT.to_bytes(2, 'little') for n in range(256))
        mu.mem_write(0, ivt)
        equip = 0x0020 | 0x0C       # 80x25 colour, RAM bits
        if self.floppies:
            equip |= 0x0001 | ((self.floppies - 1) << 6)
        self._w16(0x410, equip)
        self._w16(0x413, 640)
        self.mu.mem_write(0x417, b'\x00')
        self.mu.mem_write(0x449, b'\x03')
        self._w16(0x44A, 80)
        self._w16(0x463, 0x3D4)
        self._w32(0x46C, 0)
        self.mu.mem_write(0x475, b'\x00')

    def _w16(self, a, v):
        self.mu.mem_write(a, (v & 0xFFFF).to_bytes(2, 'little'))

    def _w32(self, a, v):
        self.mu.mem_write(a, (v & 0xFFFFFFFF).to_bytes(4, 'little'))

    def _r16(self, a):
        return int.from_bytes(self.mu.mem_read(a, 2), 'little')

    @property
    def ticks(self):
        return int.from_bytes(self.mu.mem_read(0x46C, 4), 'little')

    def _advance_ticks(self, n=1):
        self._w32(0x46C, self.ticks + n)

    # ----- register helpers
    def r(self, reg):
        return self.mu.reg_read(reg)

    def w(self, reg, v):
        self.mu.reg_write(reg, v)

    def _push(self, v):
        sp = (self.r(UC_X86_REG_SP) - 2) & 0xFFFF
        self.w(UC_X86_REG_SP, sp)
        self.mu.mem_write(self.r(UC_X86_REG_SS) * 16 + sp,
                          (v & 0xFFFF).to_bytes(2, 'little'))

    def _stacked_flags_addr(self):
        # Inside a stub: [SP]=IP, [SP+2]=CS, [SP+4]=FLAGS
        return self.r(UC_X86_REG_SS) * 16 + ((self.r(UC_X86_REG_SP) + 4) & 0xFFFF)

    def _set_ret_flags(self, set_mask=0, clear_mask=0):
        a = self._stacked_flags_addr()
        f = self._r16(a)
        self._w16(a, (f | set_mask) & ~clear_mask)

    def _ret_cf(self, cf):
        if cf:
            self._set_ret_flags(FLAG_CF)
        else:
            self._set_ret_flags(0, FLAG_CF)

    # ----- CPU event hooks
    def _on_int(self, mu, intno, _):
        """Real-mode INT: vector through the IVT like a CPU would."""
        flags = self.r(UC_X86_REG_EFLAGS) & 0xFFFF
        self._push(flags)
        self._push(self.r(UC_X86_REG_CS))
        self._push(self.r(UC_X86_REG_IP))
        self.w(UC_X86_REG_EFLAGS, flags & ~(FLAG_IF | 0x0100))
        off = self._r16(intno * 4)
        seg = self._r16(intno * 4 + 2)
        self.w(UC_X86_REG_CS, seg)
        self.w(UC_X86_REG_IP, off)

    def _on_in(self, mu, port, size, _):
        if self.ide.owns(port):
            v = self.ide.read(port)
            if size == 2:
                v |= self.ide.read(port + 1) << 8
            return v
        if port in self.pic:
            return self.pic[port]
        return 0xFF if size == 1 else 0xFFFF

    def _on_out(self, mu, port, size, value, _):
        if self.ide.owns(port):
            self.ide.write(port, value & 0xFF)
            if size == 2:
                self.ide.write(port + 1, value >> 8)
        elif port in self.pic:
            self.pic[port] = value & 0xFF

    def _on_sentinel(self, mu, addr, size, _):
        self.result = ('returned', None)
        mu.emu_stop()

    def _on_boot(self, mu, addr, size, _):
        if self.run_boot_sector:
            return
        if self.r(UC_X86_REG_CS) * 16 + self.r(UC_X86_REG_IP) == 0x7C00:
            self.result = ('boot', self.r(UC_X86_REG_DL))
            mu.emu_stop()

    def _on_stub(self, mu, addr, size, _):
        n = addr - (STUB_SEGMENT * 16 + STUB_BASE)
        handler = getattr(self, f'_int{n:02x}', None)
        if handler:
            handler()
        # The IRET byte at the stub then returns to the caller.

    # ----- BIOS services
    def _int10(self):
        ah, al = self.r(UC_X86_REG_AH), self.r(UC_X86_REG_AL)
        self.int10[ah] += 1
        self.int10_log.append((self.ticks, ah))
        s = self.screen
        if ah == 0x00:
            s.clear()
        elif ah == 0x01:
            s.cursor_shape = self.r(UC_X86_REG_CX)
        elif ah == 0x02:
            dx = self.r(UC_X86_REG_DX)
            s.row, s.col = min(dx >> 8, s.rows - 1), min(dx & 0xFF, s.cols - 1)
        elif ah == 0x03:
            self.w(UC_X86_REG_DX, (s.row << 8) | s.col)
            self.w(UC_X86_REG_CX, s.cursor_shape)
        elif ah == 0x08:
            self.w(UC_X86_REG_AX, (s.attrs[s.row][s.col] << 8) | s.chars[s.row][s.col])
        elif ah == 0x09:
            s.write_repeat(al, self.r(UC_X86_REG_BL), self.r(UC_X86_REG_CX))
        elif ah == 0x0A:
            s.write_repeat(al, None, self.r(UC_X86_REG_CX))
        elif ah == 0x0E:
            s.teletype(al)
        elif ah == 0x0F:
            self.w(UC_X86_REG_AX, (s.cols << 8) | 0x03)
            self.w(UC_X86_REG_BH, 0)
        elif ah in (0x06, 0x07):
            if al == 0 or al >= s.rows:
                s.clear()
            else:
                for _ in range(al):
                    s._scroll_up()

    def _int11(self):
        self.w(UC_X86_REG_AX, self._r16(0x410))

    def _int12(self):
        self.w(UC_X86_REG_AX, 640)

    def _int13(self):
        """The system's own (floppy) INT 13h."""
        ah, dl = self.r(UC_X86_REG_AH), self.r(UC_X86_REG_DL)
        if dl & 0x80:
            self.w(UC_X86_REG_AH, 0x01)
            self._ret_cf(True)
            return
        if ah == 0x00:
            self.w(UC_X86_REG_AH, 0)
            self._ret_cf(False)
        elif ah == 0x08:
            if dl < self.floppies:
                self.w(UC_X86_REG_BX, 0x0001)       # 360K
                self.w(UC_X86_REG_CX, 0x2709)
                self.w(UC_X86_REG_DX, 0x0100 | self.floppies)
                self.w(UC_X86_REG_AX, 0)
                self._ret_cf(False)
            else:
                self.w(UC_X86_REG_AX, 0x0100)
                self._ret_cf(True)
        elif ah == 0x15:
            self.w(UC_X86_REG_AH, 0x01 if dl < self.floppies else 0x00)
            self._ret_cf(False)
        elif ah == 0x02 and dl == 0 and self.floppies and self.floppy_bootable:
            es, bx = self.r(UC_X86_REG_ES), self.r(UC_X86_REG_BX)
            self.mu.mem_write(es * 16 + bx, bytes(510) + b'\x55\xAA')
            self.w(UC_X86_REG_AX, 0x0001)
            self._ret_cf(False)
        else:
            self.w(UC_X86_REG_AH, 0x80)             # timeout, no disk
            self._ret_cf(True)

    def _int40(self):
        self._int13()

    def _int15(self):
        self.w(UC_X86_REG_AH, 0x86)
        self._ret_cf(True)

    def _next_key_ready(self):
        return self.keys and self.keys[0][0] <= self.ticks

    def _int16(self):
        ah = self.r(UC_X86_REG_AH)
        if ah in (0x00, 0x10):
            if not self.keys:
                self.result = ('waiting-for-key', None)
                self.mu.emu_stop()
                return
            t, k = self.keys.popleft()
            if t > self.ticks:
                self._w32(0x46C, t)
            self.events.append((self.ticks, 'key', k))
            self._key_mark = (k, len(self.int10_log))
            self.w(UC_X86_REG_AX, KEYS[k])
        elif ah in (0x01, 0x11):
            self.polls.append(self.ticks)
            if self._key_mark is not None:
                k, mark = self._key_mark
                self.key_costs.append((k, len(self.int10_log) - mark))
                self._key_mark = None
            if self._next_key_ready():
                self.w(UC_X86_REG_AX, KEYS[self.keys[0][1]])
                self._set_ret_flags(0, FLAG_ZF)
            else:
                self._set_ret_flags(FLAG_ZF)
        elif ah == 0x02:
            self.w(UC_X86_REG_AL, 0)

    def _int18(self):
        self.result = ('int18', None)
        self.mu.emu_stop()

    def _int19(self):
        self.result = ('system-int19', None)
        self.mu.emu_stop()

    def _int1a(self):
        if self.r(UC_X86_REG_AH) == 0x00:
            t = self.ticks
            self.w(UC_X86_REG_CX, t >> 16)
            self.w(UC_X86_REG_DX, t & 0xFFFF)
            self.w(UC_X86_REG_AL, 0)

    # ----- running
    def _run(self):
        self.result = None
        while self.result is None:
            if self.ticks >= self.max_ticks:
                self.result = ('tick-budget', None)
                break
            start = self.r(UC_X86_REG_CS) * 16 + self.r(UC_X86_REG_IP)
            try:
                self.mu.emu_start(start, 0xFFFFFFFF, count=INSNS_PER_TICK)
            except UcError as e:
                cs, ip = self.r(UC_X86_REG_CS), self.r(UC_X86_REG_IP)
                self.result = ('cpu-error', f'{e} at {cs:04X}:{ip:04X}')
                break
            if self.result is None:
                self._advance_ticks()
        return self.result

    def boot(self):
        """ROM scan call, then INT 19h. Returns the final result tuple."""
        self.w(UC_X86_REG_SS, 0x0030)
        self.w(UC_X86_REG_SP, 0x0100)
        self.w(UC_X86_REG_EFLAGS, 0x0202)
        self._push(STUB_SEGMENT)
        self._push(SENTINEL_OFS)
        self.w(UC_X86_REG_CS, ROM_SEGMENT)
        self.w(UC_X86_REG_IP, 3)
        res = self._run()
        if res[0] != 'returned':
            return res
        self.events.append((self.ticks, 'rom-init-done', None))
        # The system BIOS now runs INT 19h.
        self.w(UC_X86_REG_IP, SENTINEL_OFS)
        self.w(UC_X86_REG_CS, STUB_SEGMENT)
        self._on_int(self.mu, 0x19, None)
        return self._run()


def make_drives(count):
    drives = [AtaDrive('RIVET TEST DISK 0', 615, 4, 17),
              AtaDrive('RIVET TEST DISK 1', 977, 5, 17)][:count]
    for d in drives:
        d.write(0, bytes(510) + b'\x55\xAA')      # bootable sector 0
    return drives


def menu_profile(m):
    """Split INT 10h calls into: initial menu draw (up to the first key
    poll), idle calls per tick while waiting, and calls per key press."""
    log = m.int10_log
    if not m.polls:
        return None
    first_poll = m.polls[0]
    keys = [t for t, kind, _ in m.events if kind == 'key']
    initial = sum(1 for t, _ in log if t <= first_poll)
    end_idle = keys[0] if keys else m.ticks
    idle_calls = sum(1 for t, _ in log if first_poll < t < end_idle)
    idle_ticks = max(1, end_idle - first_poll - 1)
    return {'initial_draw': initial,
            'idle_per_second': round(idle_calls / idle_ticks * 18.2, 1),
            'idle_window_ticks': idle_ticks,
            'per_key': m.key_costs}


def parse_keys(spec):
    """'5:down,6:down,8:enter' -> [(5,'down'), ...]; ticks are absolute."""
    out = []
    if not spec:
        return out
    for item in spec.split(','):
        t, k = item.split(':')
        out.append((int(t), k.strip().lower()))
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('rom')
    ap.add_argument('--hispeed', action='store_true',
                    help='XT-IDE board jumpered for HI-SPEED')
    ap.add_argument('--drives', type=int, default=1, choices=(0, 1, 2))
    ap.add_argument('--floppies', type=int, default=1)
    ap.add_argument('--keys', default='',
                    help='tick:key list, e.g. 40:down,60:enter')
    ap.add_argument('--max-ticks', type=int, default=1200)
    ap.add_argument('--boot-floppy', action='store_true',
                    help='put a bootable disk in drive A:')
    a = ap.parse_args(argv[1:])
    drives = make_drives(a.drives)
    drives += [None] * (2 - len(drives))
    m = Machine(open(a.rom, 'rb').read(), drives, a.hispeed, a.floppies,
                parse_keys(a.keys), a.max_ticks,
                floppy_bootable=a.boot_floppy)
    res = m.boot()
    print(m.screen.text())
    print('-' * 80)
    print('result:', res, 'ticks:', m.ticks)
    print('INT 10h calls:', dict(sorted(m.int10.items())),
          'total', sum(m.int10.values()))
    print('IDE commands:', ' '.join(f'{c:02X}' for c in m.ide.log))
    print('menu profile:', menu_profile(m))
    return 0 if res[0] in ('boot', 'waiting-for-key', 'tick-budget') else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
