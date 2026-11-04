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
* v0.4.0: images can be built without the boot menu, booting in BIOS
  order instead; in the boot menu, any keypress stops the selection
  timeout (see below)

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
make nomenu     # build only the images without the boot menu
make check      # build, then check images against the known-good baseline
make emutest    # build, then run behaviour tests on an emulated XT
make clean      # remove Build/
```

Each build produces twelve 8 KB images with the option ROM checksum set.
Their names are `Build/rivet_<cpu>[_hs][_nomenu].bin`:

| Name part | Meaning                                                    |
|-----------|------------------------------------------------------------|
| `xt`      | 8086/8088                                                  |
| `xtp`     | 80186/80188, NEC V20/V30 and later                         |
| `at`      | 80286 and later                                            |
| `_hs`     | XT-IDE HI-SPEED mode (without it: NORMAL mode)             |
| `_nomenu` | no boot menu; boots in BIOS order (without it: boot menu)  |

For example, `rivet_xt.bin` is the 8088 image for a NORMAL-mode XT-IDE
with the boot menu, and `rivet_xtp_hs_nomenu.bin` is the V20 image for a
HI-SPEED board without it.

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

`make check` compares all twelve images against `Tools/baseline.sha256`. If
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
mismatched NORMAL/HI-SPEED image finds no drives, that the idle menu
isn't redrawing constantly, and that the no-menu images boot in BIOS order.
CI runs it on every push.

This is a test harness, not an accurate emulator: it doesn't model timing,
so it can't measure speed. Real hardware is still the release test.

## Boot menu

The boot menu keeps the v1.1.5 look and keys. One behaviour change since
v0.4.0: **any keypress stops the selection timeout for good**, and the
countdown disappears from the bottom border. It stays stopped if the menu
is shown again during the same boot (after Esc, or after a failed boot).
Keys already waiting in the keyboard buffer when the menu opens, such as
ones pressed during POST, are discarded first, so a stray keypress can't
stop an unattended boot. Keys pressed while the menu is being drawn still
count.
v1.1.5 only restarted the countdown on a selection change, so anyone who
needed time, for example to fetch a boot floppy, had to keep pressing
arrow keys.

Since v0.3.0 the menu is drawn by purpose-built code
(`Src/Boot/BootMenuUI.asm`) instead of the generic v1.1.5 menu library,
and it only redraws what changes:

* the timeout digits only when the displayed seconds change (v1.1.5
  redrew the whole bottom border 18 times a second),
* on a selection change, only the two arrows, the drive numbers and the
  info box (v1.1.5 redrew every menu item),
* the rest of the menu only when it scrolls.

In emulator tests, the menu now makes about 3 to 4 BIOS video calls per
second while waiting (v0.2.0 made about 780), and about 130 per arrow key
(v0.2.0 made about 300). All output still goes through the video BIOS
(`INT 10h` set-cursor and teletype), so serial-console systems keep working.

### Building without the boot menu

The `_nomenu` images (built with `NO_BOOT_MENU` defined) leave the boot
menu out completely, which frees about 2.8 KB. They boot the way the
system BIOS does: from A: if it holds a bootable disk, otherwise from the
first hard disk. There is no prompt and no wait, and nothing is printed
after drive detection unless the hard disk can't be booted. Then one line
gives the reason, for example `Can't boot hard disk 80h: error 20h` (the
INT 13h error code) or `Can't boot hard disk 80h: no boot sector`. It
stays on screen for about 2 seconds before the system's INT 18h handler
takes over, since on IBM machines that starts ROM BASIC, which clears the
screen. An empty or unbootable A: is
normal and isn't reported.

Settings that only the boot menu uses (default boot drive, menu height,
selection timeout, ROM Boot item, drive info, drive number translation)
have no effect in these images, and a boot loader setting of "boot menu"
acts as "simple".

Drive number translation is what lets the menu boot a drive other than
the first one, by swapping its number with 00h or 80h. Without the menu
nothing sets up a swap, so the no-menu images leave it out. That also
lets INT 13h calls for drives Rivet doesn't handle (floppies, or drives
belonging to another option ROM) go straight to the previous handler,
which returns directly to the caller instead of back through Rivet.
Sharing INT 13h with other option ROMs works the same either way; that is
handled separately, by numbering Rivet's drives after the ones already
present and passing other drives' calls along. The ROM
header says which kind of image it is, in the read-only `wBuildFlags`
field at offset 59h: bit 0 (`FLG_BUILD_NOBOOTMENU`) is set in `_nomenu`
images. A configuration program uses this to show only the settings that
apply. Zero means a full build, so images from before the field existed
read correctly.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report bugs and submit
patches, the source-file conventions, and the policy on AI-assisted
contributions.

## License

Rivet is distributed under the GNU General Public License, version 2. See
`gpl-2.0.txt`.

XTIDE Universal BIOS v1.1.5 is Copyright (C) 2009-2010 Tomi Tilli.
Modifications are Copyright (C) 2026 Glitch Works, LLC.
