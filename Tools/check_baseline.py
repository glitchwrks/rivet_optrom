#!/usr/bin/env python3
"""Check built images against the known-good hashes in a baseline file.

The baseline file uses sha256sum format ("HASH  PATH" per line). Lines that
are blank or start with '#' are ignored. Exits non-zero, listing each
mismatch, if any image is missing or its hash doesn't match. Prints nothing
on success unless -v is given.

Copyright (C) 2026 Glitch Works, LLC

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License version 2 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.
"""

import hashlib
import sys


def main(argv):
    args = [a for a in argv[1:] if a != "-v"]
    verbose = "-v" in argv[1:]
    if len(args) != 1:
        print("usage: check_baseline.py [-v] BASELINE_FILE", file=sys.stderr)
        return 2

    failures = 0
    with open(args[0]) as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                expected, path = line.split(None, 1)
            except ValueError:
                print(f"{args[0]}:{lineno}: malformed line", file=sys.stderr)
                return 2
            try:
                with open(path, "rb") as img:
                    actual = hashlib.sha256(img.read()).hexdigest()
            except FileNotFoundError:
                print(f"MISSING  {path}", file=sys.stderr)
                failures += 1
                continue
            if actual != expected.lower():
                print(f"MISMATCH {path}", file=sys.stderr)
                print(f"  expected {expected}", file=sys.stderr)
                print(f"  got      {actual}", file=sys.stderr)
                failures += 1
            elif verbose:
                print(f"OK       {path}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
