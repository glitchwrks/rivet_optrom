# Rivet

Rivet is an ATA option ROM for PC/XT-class machines. It's for use with
XT-IDE and compatible controllers.

Rivet is derived from the XTIDE Universal BIOS v1.1.5 by Tomi Tilli. Glitch
Works, LLC maintains it. It is a separate project from the XTIDE Universal
BIOS, so please don't report Rivet issues upstream.

## Status

Early days. Rivet v0.1.0 is the XTIDE Universal BIOS v1.1.5 code with a
new identity. The boot screen shows `-=Rivet Option ROM (XT)=-` (or
`(XT+)` / `(AT)`) and version `v0.1.0`, and the ROM carries the
configuration signature `RIVET010` (not upstream's `XTIDE110`).
The code is otherwise unchanged from v1.1.5, apart from build changes so
it assembles with NASM on Unix-like systems.

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

Each build produces three 8 KB images with the option ROM checksum set:

| Image                 | Target CPU                                |
|-----------------------|-------------------------------------------|
| `Build/rivet_xt.bin`  | 8086/8088                                 |
| `Build/rivet_xtp.bin` | 80186/80188, NEC V20/V30 and later        |
| `Build/rivet_at.bin`  | 80286 and later                           |

### Baseline check

`make check` compares all three images against `Tools/baseline.sha256`. If
it fails, something changed the build output that wasn't meant to. Common
causes are a source edit or a different assembler. Intended changes to the
ROM update the baseline in the same commit.

The v0.1.0 baseline images differ from the official v1.1.5 release images
only in the ROM header identity (date, signature, title and version) and
the checksum byte.

Register-to-register `XCHG` instructions have two valid encodings, and
NASM and YASM pick different ones. Some `XCHG` operands in the source are
in the order that makes NASM match the original YASM-built release, so
please don't "tidy" them.

## License

Rivet is distributed under the GNU General Public License, version 2. See
`gpl-2.0.txt`.

XTIDE Universal BIOS v1.1.5 is Copyright (C) 2009-2010 Tomi Tilli.
Modifications are Copyright (C) 2026 Glitch Works, LLC.
