# Arcade

Arcade games from your Omarchy bar.

- **Nine original games** play the moment you install, with nothing else needed:
  - **Brick Blitz** (brick-breaker)
  - **Circuit Crawl** (maze chase)
  - **Lattice Siege** (formation shooter)
  - **Glintfall** (falling blocks)
  - **Solder Snap** (match-three)
  - **Super MMA Fighter** (1-on-1 MMA)
  - **Tetherwake** (vector space shooter)
  - **Dockhop** (lane crossing)
  - **Surge Rink** (air hockey)
- **Pac-Man**, **Galaga** and **Super Street Fighter II** launch in MAME from your own
  ROM files. Arcade installs MAME for you the first time you pick one, checks your ROMs
  and tells you exactly what's missing.

An Omarchy.Fans product by ModPunk. MIT licensed, free, no account.

> Arcade never downloads, links to or includes game ROMs. The built-in games are our own:
> original names, characters, levels and looks. The MAME launchers only start games from
> files you already have.

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
problem in the game can't affect your desktop. So does every built-in game.

## More built-in games

Every built-in game shares these keys: **P** pauses, **Esc** quits, and **Enter** plays
again after a game over. A game also pauses when its window loses focus. High scores
are saved in `~/.local/state/omarchy-arcade/<game>.json`, and colors follow your
Omarchy theme.

### Circuit Crawl: maze chase

You're **Byte**, a little robot collecting bits on a circuit board.
- **Four bugs** hunt you, each in its own way:
  - **Null** heads straight for you.
  - **Race** cuts you off.
  - **Leak** wanders.
  - **Loop** guards its corner until you come close.
- **Debug chips** make the bugs squashable for a while; squash all four on one chip for
  a bonus.
- **Coffee** turns up twice per level; it scores points and overclocks Byte.
- Two boards, *Motherboard* and *Northbridge*, get faster each level.

Arrows or WASD steer. A turn is remembered until the next junction.

### Lattice Siege: formation shooter

Geometric enemies (nodes, relays and prisms) fly in on curved paths and wire themselves
into **constellations**.
- Destroy a whole constellation quickly (a **link snap**) to earn a **wing drone**. Up to
  two fly beside your cannon, fire with it, and take a hit for you.
- Squads dive together from stage 3, and every fourth stage brings a boss.

Left/right or A/D move; Space fires (hold to keep firing).

### Glintfall: falling blocks

A **12-column well** and a family of **ten pieces of three and five cells**.
- Some pieces carry a **glint** cell. Clearing a row with a glint in it **bursts** the
  area around it for bonus points, and chained bursts score more.
- Hold a piece (**C** or Shift), and see the next three coming.

Left/right move, Up/X turn, Z turns back, Down soft-drops, Space hard-drops.

### Solder Snap: match-three

Swap circuit parts (resistors, capacitors, LEDs, chips and transistors) to line up three
or more.
- Lines of four build **bus** parts that clear a row or column, and L/T shapes build
  bigger specials.
- **Fried parts** block the board until a match next to them repairs them.
- Fill the **flux** meter to **Reroute**: turn a 2×2 block for free.
- Each level has a goal and a move limit.

Use the mouse (drag or click two parts), or the arrows plus Space. R reroutes and H
shows a hint.

### Super MMA Fighter: 1-on-1 MMA

Seven invented fighters, one per fighting style: a sambo grinder, a power counter-puncher,
a rangy technician, a kickboxing sniper, a heavy hitter, a submission artist and a judo
thrower.

Each fighter's ratings and finish split are **anonymous averages of real elite fighters'
public records** in that style. That means the numbers behind power, speed, kicks, clinch,
wrestling, grappling, cardio and defense, and each fighter's share of KO, submission and
decision wins. The character-select screen shows them the classic way.

Those numbers drive everything: damage, stamina, takedown and submission odds, and how
the CPU fights you. No fighter depicts a real person.

- **Stand-up:** jabs, crosses, hooks, body shots, leg, body and head kicks, knees, blocks and
  slip-counters.
- **Clinch and takedowns:** knees and throws in the clinch; sprawl to stop a shot.
- **Ground:** guard, half guard, side control, mount and back, with ground-and-pound.
- **Submissions:** a tug of war. The attacker squeezes, the defender mashes to escape, and
  a full meter is a **TAP OUT**.
- **Rounds:** three, on a clock. Any fight that isn't finished goes to three judges, and the
  decision can be unanimous, split or a draw.

Modes: a ladder against the CPU (Easy, Normal or Hard), or two players on one keyboard.
- **P1:** WASD, F strike, G kick, H special, J grapple.
- **P2:** arrows, Ctrl strike, Shift kick, Enter special, `/` grapple.

The select screen lists every move.

### Tetherwake: vector space shooter

Pilot a skiff through wrap-around space full of shattering debris and sleeping mines.
- Your **tether** (Shift, Down or S) hooks debris or a mine and tows it on a spring line.
  Press again to **fling** it.
- A towed mine is disarmed until it hits something, and then it blows for double points.
- Mines chain-react, ion gusts push you around, and from wave 4 a carrier crosses the field
  laying mines.

Left/right rotate, Up thrusts, Space fires.

### Dockhop: lane crossing

Guide a courier bot across lanes of warehouse traffic, then over a shaft of moving
pallets and conveyors, into the dock bays at the top before the shift clock runs out.
- **Boost** (Space) leaps two tiles.
- Carry a **parcel** home for a bonus.
- From shift 2, **flicker pads** power down under you.
- Faster parking pays more.

Arrows or WASD hop one tile.

### Surge Rink: air hockey

First to seven on a top-down rink.
- Hold the surge key to charge a **SURGE** smash.
- Glancing hits put **swerve** on the puck and make it curve.
- A shot clock stops anyone stalling in their own half.

Play the CPU up a ladder of tiers, or two players on one keyboard.
- **P1:** WASD plus F/G/H or Space to surge. In one-player mode the mouse also works.
- **P2:** arrows plus Ctrl/Shift/Enter.

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
