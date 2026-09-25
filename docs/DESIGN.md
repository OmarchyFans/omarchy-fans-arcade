# Arcade — design

Status: **design phase**, 2026-09-24. Nothing here is built yet.

## Principles

1. **Ship a client, not a library.** The legal constraints in [LEGAL.md](LEGAL.md)
   are not a limitation to work around — they are the architecture.
2. **Useful with zero server.** Local play, couch co-op, and verified score attack all
   work offline, with no account. The hosted pieces are additive.
3. **Curation is the product.** MAME supports roughly forty thousand sets; a few
   hundred are worth competitive play. "Thousands of games" is a liability. The
   catalog's value is knowing which titles have rollback, which have verified scores,
   which are two-player, and which ROM-set hash is the right one.
4. **Single player first.** Most users will never fight a stranger. If the solo
   experience is not excellent, none of the rest matters.
5. **Reuse the Omarchy.Fans platform.** Identity, billing, and the tenant model already
   exist. Arcade does not build a second account system.

## Shape

```
Arcade (plugin, MIT)          bar widget + panel; launcher, library, presence, queue
  |- core-installer           fetches emulators upstream, pins + verifies by hash
  |- catalog.json             romset hashes, modes, netcode support, control maps
  |- session runner           Hyprland workspace, idle-inhibit, rotation, gamepads
  |- import                   scan a user folder, hash, match to catalog

Arcade Service (hosted, optional)   reuses existing tenant + OAuth + token layer
  |- matchmaker               region- and ping-gated, Glicko-seeded
  |- relay                    NAT traversal; metered, like other hosted resources
  |- verifier                 headless re-simulation of submitted input replays
  |- ratings                  Glicko-2 per romset-hash, seasons, decay
  |- portal                   profile, stats, replays, brackets, leaderboards
```

## Decisions made

**Ranking: Glicko-2, not Elo.** A desktop-plugin audience plays in bursts. Glicko
tracks a rating deviation that inflates during layoffs and tightens with activity;
Elo treats a six-month-absent player as exactly as well-measured as a daily grinder,
which produces miscalibrated matches on a sparse ladder. Placement matches, seasonal
soft resets, and inactivity decay follow from this.

**Ratings key on ROM-set hash.** Not the display name. See README.

**Emulator per purpose, not one emulator.** Rollback-capable cores for competitive
versus; broad-compatibility cores for library depth; a hardened, pinned build for
verified score runs. These are not interchangeable and the catalog records which
applies per title.

**Replay verification over trust.** Scores are confirmed by re-simulating a
deterministic input log server-side, with the emulator build pinned and hashed per
season. Save states, pause, frame-skip, and cheats are disabled in the verified build.

**Disconnects count.** A rage-quit is a loss, tracked and shown on the profile. A
ladder without this is a joke within a week.

**Ranked is never the default.** A casual and handicap queue exists from the first day
versus play ships. New players being destroyed in their first ten matches is the
single most reliable way to kill a fighting-game community.

## The desktop problems

This is where an Omarchy plugin can win on an axis nobody else competes on. Arcade
setups on Linux usually die here:

- input latency and gamepad hotplug; per-game control maps; arcade-stick and bartop
  hardware
- audio latency through PipeWire
- **idle-inhibit during a match** — a lock mid-game is a lost match, and on some
  configurations a lock event has crashed the shell
- **rotation and bezels** — Galaga is a vertical game; on a 16:9 panel without TATE
  handling it looks broken
- CRT shaders, integer scaling, correct aspect
- a dedicated Hyprland workspace with window rules, entered and left cleanly

## Nice-to-haves, deliberately deferred

- **Achievements** — an open third-party API already covers thousands of titles with
  a large achievement corpus. Integrate; do not rebuild.
- **Tournaments** — brackets, check-in, no-show timers, seeding, disputes, and
  spectator streams are their own product. v1 integrates an existing bracket service
  or ships a minimal auto-bracket.
- **Attract mode** — idle screensaver cycling demo loops, cabinet-style.
- **Theme generation** — derive an Omarchy palette from a game's marquee, the same
  pattern Zen Wallpaper already uses.
- **Match-of-the-week on the wallpaper** — replays are small and deterministic, so
  this is close to free once replays exist.

## Roadmap

**v1 — no server required.** Local play, curated catalog, BYO-ROM import with hash
verification, couch co-op, verified score attack, attract mode.

**v2 — the social layer.** Rollback versus, Glicko-2 ladders and seasons, presence and
lobbies, spectating and replays, casual/handicap queue.

**v3 — events.** Tournaments and brackets, achievements, profile portal.

The v1/v2 split is deliberate: building matchmaking infrastructure for an audience
that turns out to want single-player Galaga is the expensive mistake available here.

## House rules

Arcade follows the Omarchy.Fans plugin conventions:

- in-app update alerts from day one, via the shared update helper
- manifest version and CHANGELOG bumped in the same change as any behaviour change
- because Arcade makes network calls, the marketplace submission carries a maintainer
  note on the security baseline
