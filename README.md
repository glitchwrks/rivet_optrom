# Rivet

Rivet is an ATA option ROM for PC/XT-class machines. It's for use with
XT-IDE and compatible controllers.

Rivet is derived from the XTIDE Universal BIOS v1.1.5 by Tomi Tilli. Glitch
Works, LLC maintains it. It is a separate project from the XTIDE Universal
BIOS, so please don't report Rivet issues upstream.

## Status

Early days. Rivet is based on the XTIDE Universal BIOS v1.1.5 code, with a
new identity. The boot screen shows `-=Rivet Option ROM (XT)=-` (or
`(XT+)` / `(AT)`) and the Rivet version, and the ROM carries the
configuration signature `RIVET010` (not upstream's `XTIDE110`).

Changes from v1.1.5:

* v0.1.0: new identity; builds with NASM on Unix-like systems
* v0.2.0: support for XT-IDE boards jumpered for HI-SPEED mode (see below)
* v0.3.0: new boot menu code. It looks and behaves the same, but only
  redraws what changes, which makes it much faster on 4.77 MHz machines
  (see below)

**Configuration:** the XTIDE Universal BIOS configurator (XTIDECFG) only
recognizes ROMs with its own signature, so it can't configure or flash
Rivet images. A Rivet configuration program is planned. Until it exists,
Rivet images run with their built-in default settings.

## Building

Requirements:

* GNU make
* [NASM](https://www.nasm.us/)
* Python 3, for the checksum and baseline-check tools
* Optional: the Python [unicorn](https://www.unicorn-engine.org/) package,
  for `make emutest`

Tested with NASM 2.15.05 and 2.16.01.

```
make build      # build all images into Build/
make check      # build, then check images against the known-good baseline
make emutest    # build, then run behaviour tests on an emulated XT
make clean      # remove Build/
```

Each build produces six 8 KB images with the option ROM checksum set:

| Image                    | Target CPU                         | XT-IDE mode |
|--------------------------|------------------------------------|-------------|
| `Build/rivet_xt.bin`     | 8086/8088                          | NORMAL      |
| `Build/rivet_xtp.bin`    | 80186/80188, NEC V20/V30 and later | NORMAL      |
| `Build/rivet_at.bin`     | 80286 and later                    | NORMAL      |
| `Build/rivet_xt_hs.bin`  | 8086/8088                          | HI-SPEED    |
| `Build/rivet_xtp_hs.bin` | 80186/80188, NEC V20/V30 and later | HI-SPEED    |
| `Build/rivet_at_hs.bin`  | 80286 and later                    | HI-SPEED    |

The XT and XT+ images expect one XT-IDE at 300h. The AT images expect
standard IDE at 1F0h/IRQ 14 and 170h/IRQ 15, plus an XT-IDE at 300h.

### XT-IDE NORMAL and HI-SPEED modes

XT-IDE rev 3 and rev 4 boards have jumpers for two register layouts:

* **NORMAL** (default strapping): the original XT-IDE layout. The IDE data
  high byte is latched at base+8. Use the plain images.
* **HI-SPEED** ("Chuck mod"): ISA A0 and A3 are swapped, which moves the
  data high byte to base+1. Use the `_hs` images.

In HI-SPEED mode, reads use 16-bit `IN`/`INSW`, which the CPU turns into
two back-to-back 8-bit bus cycles. Writes still go high byte first, then
low byte, because writing the low byte starts the IDE write cycle. The
other IDE registers are remapped by swapping A0 and A3 of the port
address, which requires the board's base address to be a multiple of 16
(it always is on XT-IDE).

The image's mode must match the board's jumpers. A mismatched image won't
find any drives.

The boot menu shows the bus as `D8` for NORMAL and `H8` for HI-SPEED.

### Baseline check

`make check` compares all six images against `Tools/baseline.sha256`. If
it fails, something changed the build output that wasn't meant to. Common
causes are a source edit or a different assembler. Intended changes to the
ROM update the baseline in the same commit.

The v0.1.0 images differed from the official v1.1.5 release images only in
the ROM header identity (date, signature, title and version) and the
checksum byte. From v0.2.0 on, the code differs too, as described in git
history.

Register-to-register `XCHG` instructions have two valid encodings, and
NASM and YASM pick different ones. Some `XCHG` operands in the source are
in the order that makes NASM match the original YASM-built release, so
please don't "tidy" them.

### Emulator tests

`Tools/xtemu.py` runs a ROM image on an emulated PC/XT. The CPU is
emulated with Unicorn, the BIOS services are stubbed in Python, and there
is a simple model of an XT-IDE board with ATA drives (NORMAL or HI-SPEED
layout). It captures the 80x25 screen and counts every `INT 10h` call, so
two builds can be compared screen for screen and by how much BIOS output
they do. For example:

```
python3 Tools/xtemu.py Build/rivet_xt.bin --drives 2 --keys 40:down,60:enter
python3 Tools/xtemu.py Build/rivet_xt_hs.bin --hispeed
```

`make emutest` (`Tools/emu_test.py`) uses it to check that each image boots
through the menu, that navigation, hotkeys and the timeout work, that a
mismatched NORMAL/HI-SPEED image finds no drives, and that the idle menu
isn't redrawing constantly. CI runs it on every push.

This is a test harness, not an accurate emulator: it doesn't model timing,
so it can't measure speed. Real hardware is still the release test.

## Boot menu

The boot menu keeps the v1.1.5 look, keys and behaviour. Since v0.3.0 it is
drawn by purpose-built code (`Src/Boot/BootMenuUI.asm`) instead of the
generic v1.1.5 menu library, and it only redraws what changes:

* the timeout digits only when the displayed seconds change (v1.1.5
  redrew the whole bottom border 18 times a second),
* on a selection change, only the two arrows, the drive numbers and the
  info box (v1.1.5 redrew every menu item),
* the rest of the menu only when it scrolls.

In emulator tests, the menu now makes about 3 to 4 BIOS video calls per
second while waiting (v0.2.0 made about 780), and about 130 per arrow key
(v0.2.0 made about 300). All output still goes through the video BIOS
(`INT 10h` set-cursor and teletype), so serial-console systems keep working.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report bugs and submit
patches, the source-file conventions, and the policy on AI-assisted
contributions.

## License

Rivet is distributed under the GNU General Public License, version 2. See
`gpl-2.0.txt`.

XTIDE Universal BIOS v1.1.5 is Copyright (C) 2009-2010 Tomi Tilli.
Modifications are Copyright (C) 2026 Glitch Works, LLC.
