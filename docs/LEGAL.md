# Legal position

This document states what Arcade distributes, what it does not, and why. It is the
constraint the rest of the architecture is built around. Read it before proposing any
feature that involves shipping content.

**This is engineering documentation, not legal advice.**

## The short version

> Arcade distributes **no game data and no emulator binaries**. It distributes a
> catalog of metadata and hashes, plus code that runs on the user's machine and
> operates on content the user already has.

## What 0.1.0 ships

- **Brick Blitz**, an original game written for Arcade under the MIT license. It is not a
  copy of any commercial title and doesn't use one's name, art or code.
- **Launchers** that start MAME, which the user installs from their own distribution,
  with ROM files the user supplies. Arcade checks those files with MAME's own
  `-verifyroms`. It never downloads, links to or bundles them.

## Why

### Game ROMs are not free, and will not be for decades

MAME is open source. The games it emulates are not. The MAME project distributes a
small set of titles whose rights holders granted permission, and that permission is
explicitly narrow — approved for distribution *from the MAME site only*, and not for
inclusion in other software, distributions, cabinets, or products.

Copyright on anything published after 1964 in the US runs 95 years from publication.
The earliest arcade titles do not enter the public domain until the 2060s. Pac-Man,
Galaga, and Street Fighter are also live trademarks whose holders actively enforce
them. There is no interpretation under which a plugin can bundle these.

### The best netcode core cannot be redistributed either

FinalBurn Neo has the strongest rollback implementation available, and it is released
under a **non-commercial license** — redistributions may not be sold or used in a
commercial product or activity. The maintainers' stated position is that other
frontends are fine so long as they do not redistribute the core; manual installation
by the user is the supported path.

Arcade therefore **fetches cores from upstream at install time, on the user's
machine**, pinned to a known version and verified by hash. It never vendors them and
never re-hosts them.

### Trademarks extend to presentation

Shipping copyrighted box art, marquees, logos, or title screens is the fastest route
to a takedown — and it would take down the *marketplace listing*, not just this repo.
Arcade ships none. Artwork is derived from the user's own files, or fetched on an
explicit opt-in basis.

## Rules for contributors

These are hard rules. A pull request that breaks one will be closed.

1. **Never commit game data.** No ROMs, CHDs, BIOS files, save states, or archives.
   `.gitignore` blocks the common extensions; do not work around it.
2. **Never vendor an emulator binary or its source.** Fetch upstream, pin, verify.
3. **Never ship copyrighted artwork.** No box art, marquees, logos, or screenshots of
   commercial titles in this repository or in any release artifact.
4. **The catalog holds metadata and hashes only.** A hash identifies a file; it is not
   the file, and it lets Arcade verify what a user already owns.
5. **Do not link to infringing sources.** No ROM sites in code, docs, issues, or the
   catalog.
6. Treat the free-content bundle as a **curated allowlist**: each entry needs a
   recorded upstream source and license before it is added.

## Naming

The product is "Arcade" and describes itself by what it does. It does not borrow the
name, styling, or iconography of any commercial title or hardware manufacturer, and
does not imply endorsement by or affiliation with any rights holder.
