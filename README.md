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

**Configuration:** the XTIDE Universal BIOS configurator (XTIDECFG) only
recognizes ROMs with its own signature, so it can't configure or flash
Rivet images. A Rivet configuration program is planned. Until it exists,
Rivet images run with their built-in default settings.

## Building

Requirements:

* GNU make
* [NASM](https://www.nasm.us/)
* Python 3, for the checksum and baseline-check tools

Tested with NASM 2.15.05 and 2.16.01.

```
make build      # build all images into Build/
make check      # build, then check images against the known-good baseline
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

## Contributing

When you modify a source file inherited from v1.1.5 for the first time, add
a line under its `Author` header:

```
; Modified		:	2026 by Glitch Works, LLC for Rivet (see git history)
```

GPLv2 section 2(a) requires changed files to say they were changed. The
line only needs adding once per file, since git history records the
individual changes. Source files use CRLF line endings, so keep them that
way.

## License

Rivet is distributed under the GNU General Public License, version 2. See
`gpl-2.0.txt`.

XTIDE Universal BIOS v1.1.5 is Copyright (C) 2009-2010 Tomi Tilli.
Modifications are Copyright (C) 2026 Glitch Works, LLC.
