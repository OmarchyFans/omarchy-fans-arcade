# Arcade

**The open arcade for Omarchy.** Play the classics, fight your friends with rollback
netcode, and climb verified leaderboards — from your desktop, with no account required
to start.

An Omarchy.Fans product by ModPunk. MIT licensed.

> **Status: design phase.** This repository currently holds the architecture and the
> legal position. No plugin code has shipped yet. See [docs/DESIGN.md](docs/DESIGN.md)
> for the full build plan and [docs/LEGAL.md](docs/LEGAL.md) for what Arcade will and
> will not distribute.

---

## What Arcade is

Arcade is a **client**, not a game library. It ships:

- a **curated catalog** — metadata, ROM-set hashes, control maps, and per-title notes
  on which games support rollback netplay, verified scores, 2-player versus, or co-op
- a **core installer** that fetches emulators from upstream, on your machine, pinned
  and hashed
- a **session runner** that makes games behave correctly on a Wayland desktop —
  rotation for vertical games, low-latency input and audio, gamepad hotplug, a
  dedicated workspace, and idle-inhibit so your screen never locks mid-match
- **three competition modes**, because arcade games are not one thing (see below)

## What Arcade is not

**Arcade ships no ROMs and no emulator binaries.** Not one. This is a deliberate
architectural decision, not an oversight — see [docs/LEGAL.md](docs/LEGAL.md).

You bring your own dumps. Arcade hashes them, matches them to the catalog, and tells
you what you can play. For an empty install, a one-click fetch pulls the genuinely
free content — the MAME project's freely-licensed titles, open-source arcade games,
and the homebrew scene — so there is something playable in thirty seconds.

---

## Three modes, three leaderboards

A single "Elo score" does not describe arcade gaming. Arcade models three distinct
kinds of competition:

| Mode | Examples | How you are ranked |
|---|---|---|
| **Versus** | Street Fighter II, NeoGeo fighters, Bomberman | Glicko-2 rating, per ROM-set, seasonal |
| **Score attack** | Galaga, Pac-Man, Donkey Kong | Verified high score from a re-simulated input replay |
| **Co-op** | Metal Slug, TMNT, beat-'em-ups | Shared clear time and depth on a party board |

Ratings are keyed on the **ROM-set hash**, never the display name. "Pac-Man" is twenty
different sets with different difficulty; "Street Fighter II" spans six revisions with
materially different balance. A leaderboard that ignores this is meaningless.

## Verified scores

Score-attack leaderboards are worthless if anyone can type a number into them. Arcade
follows the approach the MAME Action Replay Page and Twin Galaxies have used for
twenty-five years:

1. You play on a hardened, pinned emulator build with save-states, pause, frame-skip
   and cheats disabled.
2. The run is captured as a deterministic **input log** — a few kilobytes, not a video.
3. The server **re-simulates the input log headlessly** and confirms the score.

Because input logs desync across emulator versions, the emulator build is pinned and
hashed per season. A side effect: every match and every run is a tiny replay file, so
spectating and match-of-the-week are nearly free.

## Rollback netplay

Versus play uses rollback netcode, which is the only thing that makes a stranger on
the internet feel like a person sitting next to you. Rollback needs low round-trip
latency, so matchmaking is **region-aware and ping-gated** — a global queue that pairs
players who physically cannot play each other is worse than no queue at all.

Peer-to-peer connections need NAT traversal. Most succeed directly; the rest need a
relay, which is an optional hosted service. **Arcade works fully offline and on a LAN
with no account and no server.**

---

## Roadmap

**v1 — no server required**
Local play · curated catalog · bring-your-own-ROM import with hash verification ·
couch co-op with two gamepads · score attack with verified leaderboards · attract mode

**v2 — the social layer**
Rollback versus · Glicko-2 ladders and seasons · presence and lobbies · spectating and
replays · casual/handicap queue so new players are not destroyed in their first ten
matches

**v3 — events**
Tournaments and brackets · achievements integration · profile portal and stats

## Install

Not yet published. When it ships, it will be available through the Omarchy plugin
marketplace and, like every Omarchy.Fans plugin, it will tell you in-app when a new
version is out.

## License

MIT — see [LICENSE](LICENSE). The license covers Arcade's own code and catalog
metadata. It does not and cannot cover game data, which Arcade never distributes.
