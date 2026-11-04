# Contributing to Rivet

Bug reports, test results and patches are all welcome. Rivet runs on real,
old hardware that nobody can fully reproduce, so a careful report from a
real machine is often worth more than code.

## Reporting bugs

Please open a GitHub issue. If you can't use GitHub, email or DM works too
(see the README). Include:

- The machine, its BIOS, CPU (8088, V20, 286, ...) and video card
- The XT-IDE board revision and its NORMAL / HI-SPEED jumper setting, or
  the other controller you are using
- The Rivet image (`rivet_xt.bin`, `rivet_at_hs.bin`, ...) and version
- The drive (CF card, DOM, spinning disk; make and model if you know it)
- What you expected, what happened, and whether it still happens with the
  boot menu turned off

If you reported a bug against XTIDE Universal BIOS and were told it was
your hardware, report it here too.

## Patches

- Branch from the current `master` and open a pull request against it.
- `make check` and `make emutest` must pass. If you intentionally change
  the ROM image, update `Tools/baseline.sha256` in the same commit and say
  why in the commit message.
- Say what you tested, and on what. "Built only" is fine to state; it just
  needs to be stated.
- Source files use CRLF line endings. Keep them that way.
- When you modify a source file inherited from XTIDE Universal BIOS v1.1.5
  for the first time, add a line under its `Author` header:

  ```
  ; Modified		:	2026 by Glitch Works, LLC for Rivet (see git history)
  ```

  GPLv2 section 2(a) requires changed files to say they were changed. The
  line only needs adding once per file, since git history records the
  individual changes.

### Licensing

Rivet is licensed under the GNU General Public License, version 2 only.
By contributing, you state that you have the right to submit your work
under that license. Code taken from XTIDE Universal BIOS 2.x (GPLv2 or
later) is fine; say where it came from in the commit message.

## AI and other tool-assisted contributions

You may use whatever tools you like, including LLM coding assistants, but
**a human must be in the loop and is responsible for the result**. This
policy follows the approach of the [LLVM project's AI tool
policy][llvm] and the Linux kernel's [AI coding assistants][kernel]
guidance.

- **You are the author.** You are accountable for every line you submit,
  however it was produced.
- **Review it all before anyone else has to.** Read, understand and test
  everything a tool produced before you open a pull request or issue. You
  should be able to explain and defend the change in review without going
  back to the tool.
- **No slop.** Don't submit unreviewed tool output, speculative "fixes"
  you can't explain, bulk reformatting, or bug reports you haven't
  confirmed. A contribution has to be worth more than the time it takes to
  review it.
- **Disclose substantial tool use.** If a significant part of a commit was
  produced by a tool, say so in the commit message with a trailer such as
  `Assisted-by: <tool and model>`. A `Co-Authored-By:` trailer added by the
  tool is also fine. Autocomplete, spell-checking and similar don't need
  disclosing.
- **No autonomous submissions.** Bots and agents must not open pull
  requests, issues or comments on their own. A human decides what gets
  submitted.
- **Licensing still applies.** You are responsible for making sure
  tool-assisted code is compatible with GPLv2 and isn't copied from
  somewhere it can't be.

Nobody is required to use these tools. Contributions written entirely by
hand are, of course, just as welcome.

[llvm]: https://llvm.org/docs/AIToolPolicy.html
[kernel]: https://docs.kernel.org/process/coding-assistants.html
