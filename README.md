# Arcade

Arcade games from your Omarchy bar.

- **Brick Blitz**, an original brick-breaker, plays the moment you install. You don't
  need anything else.
- **Pac-Man**, **Galaga** and **Super Street Fighter II** launch in MAME from your own
  ROM files. Arcade installs MAME for you the first time you pick one, checks your ROMs
  and tells you exactly what's missing.

An Omarchy.Fans product by ModPunk. MIT licensed, free, no account.

> Arcade never downloads, links to or includes game ROMs. Brick Blitz is our own game.
> The MAME launchers only start games from files you already have.

## Install

```sh
omarchy plugin add https://github.com/OmarchyFans/omarchy-fans-arcade --enable
```

This puts the gamepad chip in your bar. Click it and pick a game.

Optionally, run the plugin's `install.sh` once in a terminal. It creates Arcade's folders
ahead of time, offers to install MAME, and tells you what's ready. Arcade works without it too:
MAME then installs itself the first time you pick a MAME game.

## Removal

```sh
~/.config/omarchy/plugins/fans.omarchy.arcade/uninstall.sh   # optional: settings and cache
omarchy plugin remove fans.omarchy.arcade
```

`uninstall.sh` keeps your Brick Blitz high score unless you add `--purge`. It never
touches your ROM folder.

## Brick Blitz

| Key | Action |
|---|---|
| ← → or A D, or the mouse | move the paddle |
| Space or click | launch the ball, let a caught ball go, or fire the laser (hold Space to keep firing) |
| Space, with nothing to launch or fire | pause |
| P | pause |
| Enter | play again after a game over |
| Esc, or close the window | quit |

- There are five layouts. After the last one they start over, a little faster.
- Tough bricks take two or three hits.
- Clearing a level gives you an extra ball, up to five.

### Power-ups

Broken bricks sometimes drop a capsule. Catch it with the paddle to use it:

| Capsule | What it does |
|---|---|
| **WIDE** | a wider paddle |
| **CATCH** | the ball sticks to the paddle; Space or a click sends it off, aimed by where it sits |
| **LASER** | Space or a click fires two bolts that break bricks |
| **SLOW** | slows the ball down |
| **MULTI** | the ball splits into three |
| **+1** | an extra ball in reserve |
| **WARP** | skip straight to the next level |

- WIDE, CATCH and LASER change the paddle, and only one can be active at a time: a new
  one replaces the old.
- Only one capsule falls at a time, and none drop while you have more than one ball.
- Losing your last ball ends every power-up.
- Each capsule you catch scores 100.
- Your high score is saved in `~/.local/state/omarchy-arcade/brick.json`.
- The colors follow your current Omarchy theme.

Brick Blitz runs as its own small Quickshell window, separate from your bar, so a
problem in the game can't affect your desktop.

## Pac-Man, Galaga and Super Street Fighter II (your own ROMs)

These run in [MAME](https://www.mamedev.org/), the open-source arcade emulator.

1. **MAME installs itself.** The first time you pick one of these games, Arcade opens a
   small terminal that installs MAME (about 460 MiB) from the official Arch repositories.
   It uses Omarchy's own `omarchy-pkg-add mame`, so your password may be asked for. When
   it's done, the game you picked starts. You can also install it yourself any time with
   `arcade install-mame`.
2. Put **your own** ROM files in `~/Games/arcade/`. The chip's *Open ROM folder* button
   opens it.

| Game | File | Also needed for split sets |
|---|---|---|
| Pac-Man | `pacman.zip`, or `puckman.zip` for a merged set | `puckman.zip` |
| Galaga | `galaga.zip` | `namco51.zip`, `namco54.zip` |
| Super Street Fighter II | `ssf2.zip` | `qsound.zip` |

**ROMs must match your MAME version.** MAME changes its ROM lists over time, so a zip made
for an older MAME can be rejected. Before starting a game, Arcade runs MAME's own ROM check.
If something is wrong, you get a notification naming the missing or bad file.

The chip's menu shows which games are ready and which ROM each still needs, and picking a game whose ROM is missing opens the ROM folder. `arcade list` shows the same in a terminal. To keep ROMs somewhere else, set
`"rom_dir": "~/path/to/roms"` in `~/.config/omarchy-arcade/config.json`.

## Command line

The plugin ships `bin/arcade`:

```
arcade play brick|pacman|galaga|ssf2
arcade list
arcade rom-dir [--open]
arcade install-mame
```

## Updates

The chip checks for a newer published version when it loads and every six hours after
that. Each check is one small request to GitHub, cached, and sends no personal data. When
a new version is out, a dot appears on the chip, and the menu shows what changed with an
**Update…** button. The update runs `omarchy plugin update`, which shows the changes and
asks before doing anything.

To turn the check off, set `"update_check": false` in
`~/.config/omarchy-arcade/config.json`, or use the widget's setting.

## What leaves your machine

- **The update check:** a request for this repository's `manifest.json`, plus
  `CHANGELOG.md` when a newer version is out.
- **Installing MAME, once:** pacman downloads the `mame` package from your configured
  Arch mirrors, like any other package.

Games, scores and ROMs stay local.

## Roadmap

Online play with rollback netcode, per-game ratings, verified leaderboards and tournaments
are planned. None of it is built yet. See [docs/ROADMAP.md](docs/ROADMAP.md) for the design,
and [docs/LEGAL.md](docs/LEGAL.md) for what Arcade will and won't distribute.

## License

MIT, see [LICENSE](LICENSE). The license covers Arcade's own code and Brick Blitz. It doesn't
and can't cover game ROMs, which Arcade never distributes.
