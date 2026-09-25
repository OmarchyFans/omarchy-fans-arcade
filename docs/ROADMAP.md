# Arcade roadmap: online play, ratings and verified scores

> **Not implemented. This is the future direction.** Arcade 0.1.0 ships Brick Blitz and
> MAME launchers for your own ROMs, and nothing described below. This document is the
> design for what comes next. Every part is subject to the gates it names.

Status: design, 2026-09-24. Reviewed adversarially once, with its findings folded in.

## Goal

Classic arcade games where Omarchy users can play each other online with low latency,
with per-game ratings, tournaments, leaderboards and a profile with stats. It's
decentralized on a Cosmos app-chain, with zk-STARK proofs for post-quantum verified
high scores.

### Hard constraints

1. **No ROMs and no emulator binaries are redistributed.** MAME's free ROMs may be
   downloaded from mamedev.org only. FBNeo is non-commercial, and its devs support only
   cores the user installs. Blockchain doesn't change this: ROMs never go on-chain, to
   IPFS, or to any server we run.
2. **Post-quantum means every layer.** CometBFT defaults are Ed25519 and secp256k1, and
   Shor's algorithm breaks both. STARKs are hash-based, so plausibly PQ, but the usual
   STARK→Groth16 wrap uses BN254 pairings and **breaks PQ**. Rules:
   - verify the **compressed recursive STARK** on-chain, with no elliptic-curve wrap;
   - use ML-DSA-65 keys from genesis (CometBFT ≥ v0.40).
3. **"zk" isn't free.** SP1's raw STARK proofs aren't zero-knowledge; SP1 gets its ZK
   from the wrap we're forbidding. A non-ZK proof can leak fragments of the witness
   (i.e. **ROM bytes**) into permanent block data. The M3 gate decides this.
4. **A proof shows execution, not a human.** A tool-assisted (TAS) or bot-generated input
   log proves perfectly. So the badge is **"verified execution"**, TAS gets its own
   category, and prize eligibility needs live-witnessed runs (§2).
5. **Marketplace layout rules:**
   - `omarchy plugin add` clones the whole repo, so the chain and its services live in a
     second repo.
   - The only `manifest.json` is the root one: the validator counts root + one level deep.
   - No symlinks. The root README covers install AND removal.
   - Bar widgets use absolute argv via `Quickshell.execDetached`, never a PATH lookup or
     `sh -c`.
   - `install.sh` never elevates privileges or installs packages.

## 1. Architecture

```
 USER'S MACHINE (repo: omarchy-fans-arcade, MIT)
 ┌──────────────────────────────────────────────────────────────────────┐
 │ Omarchy shell                                                        │
 │   BarWidget.qml ── ArcadePanel.qml (library · lobby · profile · runs)│
 │          │ execDetached(absolute argv)                               │
 │   bin/arcade (bash CLI) ──► arcade-runner (Rust, one binary)         │
 │                              ├ libretro host  ◄── user-installed     │
 │                              │                    cores (FBNeo, MAME)│
 │                              ├ arcade-core    (our provable core)    │
 │                              ├ GGRS rollback + WebRTC transport      │
 │                              ├ .arclog writer / replayer             │
 │                              ├ SDL3 video/audio/gamepad, idle-inhibit│
 │                              └ chain client (ML-DSA key in keyring)  │
 │   arcade-prover (optional, GPU box) — zkVM host + guest              │
 │   ROMs: user's folder, hashed locally, never uploaded                │
 └───────────┬──────────────────────┬──────────────────────┬────────────┘
             │ WebRTC P2P (UDP)     │ signaling/queue (WSS)│ txs / queries
             ▼                      ▼                      ▼
     other player          SERVICES (repo: arcade-chain)   ARCADE CHAIN
     (direct, or via       matchmaker+signaling (Rust)     Cosmos SDK app,
      hosted TURN relay)   TURN relays (3–5 regions)       CometBFT ≥0.40,
                           log store (content-addressed)   PoA, ML-DSA-65
                           indexer ──► portal (omarchy.fans) x/catalog x/season
                                                            x/score x/proof
                                                            x/match x/rating
                                                            x/tournament
```

**The chain is never in the gameplay path.** Frames travel P2P at the board's native
rate. The chain settles results seconds after a match ends, so block time has no effect
on latency.

| Thing | Where | Why |
|---|---|---|
| Gameplay, rollback, spectating | P2P | only way to hit frame deadlines |
| Queue, pairing, ICE signaling | matchmaker (off-chain; a named trust point) | latency-sensitive, ephemeral |
| Input logs | content-addressed store, pinned by several parties; hash on-chain | KB-sized, user-generated, safe to host |
| Catalog, seasons, runs, matches, ratings, tournaments | chain | the trust-minimized part |
| Profile text, avatars, chat, presence | off-chain | PII stays off an immutable ledger |
| ROMs | user's disk only | legal |

## 2. Competition modes → trust model

| Mode | Witnesses | Settlement | Proof? |
|---|---|---|---|
| **Versus** | 2 (both clients hold the full log) | both sign `{ticket, log_hash, checksum, result}` → settled | on dispute, and only for arcade-core titles (none of the first boards are versus) |
| **Score attack** | 1 | tiered (below) | yes, for official records |
| **Co-op** | 2–4 | all players sign | on dispute |

**Versus doesn't need zk:** two signed, agreeing clients are already strong evidence.
zk goes where there's one witness. Proving cost stays proportional to value.

### Score attack: submission (anti-theft)
Public logs make it possible to steal someone else's run. So submission is
**commit–reveal**:
1. `MsgCommitRun` puts `H(log ‖ player_addr)` on-chain.
2. Only after that is the log uploaded, followed by `MsgRevealRun`.

`player_addr` is a public input of the proof. Dedup rule: runs with the same
`(title, config, final_state_hash)` go to the earliest commitment.

### Tiers
1. **Submitted.** Signed, with a grey badge. Not ranked.
2. **Community verified.** Ranked on the everyday board.
   - The chain **assigns** 3 attesters at random from an opt-in pool, using the block
     hash as randomness, so attesters can't select themselves. Each needs a registrar
     unique-human ID different from the submitter's and from each other's.
   - After the reveal, the chain names a **challenge frame**. Attesters must return the
     state hash at that frame. That hash isn't in the submission, so it can't be signed
     without actually replaying.
   - An attester whose run later fails a proof loses attester rights.
   - There's an open challenge window. Any challenge escalates to a proof.
3. **Verified execution.** A STARK proof accepted by x/proof. This badge is required for
   season records and the all-time board.
4. **Live-witnessed** (prizes only). The run happens in a scheduled window with inputs
   streamed live through the spectator path (the matchmaker timestamps them), plus
   video, and a human reviews it. This is the Twin Galaxies model. The docs say that
   even this is not cryptographic proof that a human played.

**TAS** is a separate category with its own boards. Humanness heuristics, such as
reaction-time distributions and frame-perfect streaks, raise flags for review and never
auto-reject.

**Log availability.** A run whose log can't be fetched within T is demoted.
Verified-execution logs are pinned by validators, the indexer and the submitter.

### Versus: tickets, disconnects, disputes
- **Match tickets.** The matchmaker signs each ticket, which is single-use and bound to
  the pairing. Players can't pick their opponents, which blocks win-trading between
  their own accounts.
- **Disconnect.** One player submits the confirmed log plus their signature, and it's
  recorded as a disconnect. The rate shows on the profile. A loss applies after a
  timeout. Only patterns escalate, because a single disconnect can be a DDoS against the
  victim.
- **Conflicting results.** On arcade-core titles, the proof decides. On FBNeo/MAME
  titles, the match is voided and both players are flagged. This limitation is stated
  in the docs.

## 3. Emulation: "one core, two targets"

**Library and netplay path: the libretro host.** arcade-runner `dlopen`s libretro cores
the user installed. Rollback uses `retro_serialize`, `retro_unserialize` and a
deterministic `retro_run`, the same basis as RetroArch's rollback netplay. That gives
thousands of titles without us writing or redistributing any emulator.

**Verified path: arcade-core** (ours: MIT, Rust, `no_std`). This is a small
deterministic emulator for a curated set of boards. It's compiled **twice from one
source**: natively for play, and as the zkVM guest. Don't pin the guest ISA before M3:
recent SP1 targets RV64IM. CI runs the determinism rules on both 32- and 64-bit
targets.

We have to own this core:
- FBNeo can't be compiled into a guest we distribute, because of its license.
- A run must be *played* on the exact code that's *proven*, or the replay desyncs.
- A small, auditable core gives reproducible vkeys and cheaper proofs.

### First boards
Each board gets an inventory of every CPU and MCU and how it affects game state.

| Board | Chips | Why |
|---|---|---|
| **Namco Pac-Man hardware** | Z80 | cheapest to prove. CI uses our own homebrew test ROM, assembled in-repo (MIT) |
| **A mamedev-free Z80 board** (candidate: Robby Roto, Astrocade) | Z80 + custom | **legal day-one content** for "verified execution", since hardly anyone can legally get Pac-Man/Galaga ROMs |
| Galaga (later) | 3× Z80 **+ Namco 51xx (MB88xx MCU, handles input and credits)** + 54xx sound | the MCU affects state, so it must be emulated |
| Donkey Kong (later) | Z80 + i8035 sound | confirm the sound CPU doesn't feed back into game state |

### Determinism contract
CI enforces all of this by comparing per-frame state hashes between the native build
and the zkVM *executor* (execution without proving).
- **Boot from reset every time.** RAM is filled with a specified value, with no NVRAM
  and a defined open-bus value. The guest never accepts a start state. There is no
  `seed`.
- **Frames.** A frame is a fixed T-state count. Instruction overshoot carries over to
  the next frame deterministically. Interrupt timing is exact to the cycle, and the
  watchdog is emulated.
- **Inputs.** Inputs are latched once per frame at vblank start, and the log records
  exactly the latched value. Coin and start are logged inputs. One log entry is exactly
  one frame: the native loop never drops or doubles frames when the host stalls.
- **Code rules.** No floats in game logic, explicit wrapping arithmetic, nothing that
  depends on `usize` width, no `HashMap` iteration, no reading the clock or RNG.
  Audio and video are outputs only.
- **Idle-loop fast-forward.** A deterministic fast-forward through the busy-wait loops
  runs identically on both targets. It's likely the biggest single proving saving.

## 4. zk-STARK proving

**Public inputs**, all checked by x/proof against chain state:

| Input | Checked by x/proof |
|---|---|
| `title_id` | — |
| `romset_hash` | the guest hashes the ROM witness itself (a hacked or speed-up ROM fails), and the hash must be in the catalog's allowed romsets. The canonical order and interleave are defined in the catalog spec |
| `machine_config_hash` | DIP switches (lives, bonus, difficulty), cabinet type and player mode. Must equal the season's canonical config |
| `input_log_hash` | must match the reveal |
| `frame_count` | — |
| `final_state_hash` | — |
| `score` | the **guest extracts it from RAM** via per-title BCD addresses baked into the vkey; the submitter never claims it |
| `player_addr` | — |
| `core_vkey` | must equal the season-pinned vkey |
| `season` | — |

**Private witness:** the ROM bytes and the log. Per-frame hashing happens only in
native/executor CI. The guest hashes the final state and the log, using the zkVM's
SHA-256 precompile.

### Cost at record length
Records are what gets proven, and a perfect Pac-Man game takes 3.5–6 hours.

| Step | Figure |
|---|---|
| Z80 work | ~1 hr ≈ 11B T-states ≈ 1.4B instructions |
| RISC-V cost | × 50–100 insns each → ~70–140B cycles/hour |
| Idle-loop fast-forward | cuts that substantially (measure) |
| Proving speed | ~6–7M cycles/s per H100, plus 20–50% for recursion |
| **Per Pac-Man record** | **~10+ GPU-hours, ~$20–60** |
| Galaga | ×3–4 |
| Long runs | proved in segments (continuations) |
| Where | **GPU only**: CPU proving would take weeks |

Proving only the top N per title per season bounds the total spend.

### Who proves (legal)
The prover needs the ROM, so a shared prover pool that receives ROMs is **never** an
option. What remains:
1. **The player's own 24 GB-class GPU.** Most laptops can't do this; a typical 4 GB
   laptop GPU is far short.
2. **A private GPU machine the player controls**, such as a rented cloud GPU under their
   own account. **Needs legal review before launch.**

Disclose that verified execution effectively requires GPU access. Keep a free route:
sponsor-funded proving for the season's top N.

### M3 gate
The zkVM must pass every criterion, or "verified execution" doesn't ship.

| Criterion | Why |
|---|---|
| **Compressed recursive** STARK, verified without an elliptic-curve SNARK wrap | PQ. A raw core proof would be GB-scale |
| We build a verifier embeddable in Cosmos (Go via cgo, or Rust→wasm) with bounded time and memory | SP1's no_std verifier handles BN254 only, so **this is new work and belongs in M3** |
| Witness hiding (real ZK), or leakage quantified and legally signed off | ROM bytes would sit in permanent blocks |
| Throughput and VRAM on hardware players can actually get | cost and UX |
| Apache/MIT license; reproducible guest builds, so the published vkey matches the source | trust |

The candidates are SP1, RISC Zero and Stwo-based provers. We measure them rather than
assume.

**If none passes:** "verified execution" is replaced by community verification with
optimistic challenges, and the PQ claim is scoped to keys and signatures. That decision
is made, and published, before M4.

## 5. Low-latency multiplayer

Five stacked problems. Each has its own fix.

### 5.1 Netcode
- **Rollback, not lockstep (GGRS).** Local input applies instantly. The remote input is
  predicted by repeating the last frame. When the real input arrives, the runner
  restores the last confirmed state and re-simulates.
- **Hybrid delay.** Let L = RTT/2 and F = ⌈L / frame⌉. Then input delay D = max(1, F−4),
  and rollback covers the rest. The prediction window is at most 8 frames (the GGRS
  default). A rollback of 4 or more frames looks like teleporting, so D goes up before
  that shows. Adjust live with `set_input_delay` and tune from telemetry.
- **Time sync.** The client that's ahead waits (GGRS frame advantage).
- **Resim budget: measure p99, don't use a rule of thumb.** The cost is
  `(k+1)·run + unserialize + (k+1)·serialize`, with k = 8. It must stay ≤ ~12 ms so there
  is room to render. That works out to roughly **15–20× realtime**. The catalog stores
  the measured figure per title. Titles that fail are marked delay-only.
- **Skip A/V during resim** through `RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE`, the same
  way RetroArch run-ahead does. This avoids crackle and saves time.
- **Serialization quirks.** Honor `SET_SERIALIZATION_QUIRKS`:

  | Quirk | Response |
  |---|---|
  | `INCOMPLETE`, `SINGLE_SESSION` | no rollback |
  | `MUST_INITIALIZE` | first serialize after N frames |
  | `CORE_VARIABLE_SIZE` | re-query the size every frame |
  | `ENDIAN_DEPENDENT`, `PLATFORM_DEPENDENT` | no state transfer between peers |

  For MAME, gate per driver on its save-state support, and measure its serialize cost,
  which is much heavier than FBNeo's.
- **Identical peers.** At match start, the peers exchange these and must match:
  - the core build hash (an Arch package ≠ a buildbot build);
  - the romset hash;
  - all core options (DIPs, CPU clock, filters, frameskip), pinned per catalog title.

  Also:
  - Disable hiscore.dat and NVRAM loading. FBNeo's hiscore feature writes RAM at boot.
  - Feed a fixed synthetic time to boards with a real-time clock (the NeoGeo uPD4990).
  - Refuse threaded or hardware-render cores.
  - To rule out boot divergence completely, the host sends its serialized state after
    boot.
- **Native refresh rate.** Both peers run the title's exact rate (boards run 57–61 Hz).
- **Desync detection.** The peers exchange confirmed-state checksums every 60 frames. On
  a mismatch the match is voided and both logs are uploaded. CI runs GGRS SyncTest on
  every core marked netplay-capable.

### 5.2 Transport
- **UDP only.** A WebRTC data channel, unordered, with `maxRetransmits = 0`. ICE handles
  STUN hole-punching and the TURN fallback. Library: `str0m` or webrtc-rs, with
  Matchbox-style signaling.
- **Redundant inputs.** Every packet carries all unacknowledged inputs, so a lost packet
  costs nothing.
- **Relays.** TURN in 3–5 regions. Pick the relay that minimizes RTT(A→r) + RTT(r→B).

### 5.3 Matchmaking that respects physics
- **Estimate first.** The client pings regional UDP beacons when it joins the queue.
  The estimate for a pair is `min_r(rtt_A,r + rtt_B,r)`.
- **Measure before ranked.** An ICE connection plus 10 RTT probes, with connection bars
  shown to the player. A pair over the gate goes back in the queue.
- **Gates.** Ranked caps at **RTT 130 ms**. The search widens 60 → 90 → 130 ms, one step
  every 30 s. Casual allows up to 200 ms, labelled "laggy".
- **Density is the real enemy.** Fixes: regional "arcade nights", a friends-first queue,
  and async score duels while waiting.

### 5.4 The desktop (Omarchy's advantage)
- **Tearing.** `allow_tearing` + an `immediate` rule on the runner app-id, fullscreen
  only. VRR is off by default (its interaction with tearing is flaky) and opt-in per
  title.
- **Session wrapper.** Change options at runtime and restore them on exit, crash
  included (trap). **Never edit the user's config.** Hyprland dispatch is Lua and exits
  0 even on a parse error, so read every change back to verify it.
- **Idle-inhibit** through `SDL_DisableScreenSaver`. A lock mid-match loses it, and a lock
  during a plugin reload has crashed quickshell on this machine before.
- **Input.** SDL3 gamepad. Wired 1 kHz pads are recommended; Bluetooth adds ~8 ms.
- **Audio.** PipeWire quantum ~256 frames at 48 kHz, about 5 ms.
- **Run-ahead.** On in local and casual play. **Off in ranked and in verified runs.**
- gamemode when it's installed. The runner's workspace has no blur or animations.

### 5.5 Measure it
`arcade latency-test` flashes a patch on screen at each button press. The measurements:
- ground truth from 240 fps phone video;
- an evdev→present software estimate;
- opt-in session telemetry: RTT, rollback-depth histogram and desyncs.

Network conditions are simulated with `tc netem`.

## 6. The chain (repo: `OmarchyFans/arcade-chain`, created at M4)

- **Stack.** The current Cosmos SDK release, pinned at M4 start. CometBFT ≥ v0.40 with
  **ML-DSA-65 consensus and account keys from genesis**. The *account* side (pubkey type,
  sigverify gas, keyring) is **spiked in M0/M1**; so far only CometBFT support is proven.
  Only Arcade's own clients talk to the chain.
- **PQ scope.** Proofs, consensus signatures and account signatures are PQ. The P2P
  handshake stays classical. That's acceptable because the chain data is public anyway.
  ML-DSA-65 signatures are 3309 B (vs 64 B) and public keys 1952 B. Measure
  vote and commit bandwidth on the testnet.
- **Consensus.** The Cosmos PoA module, no token. Validators at genesis: Omarchy.Fans
  plus ≥ 4 independent operators. Governance can widen the set, and PoS or shared
  security gets evaluated after a year. The docs call this *progressive*
  decentralization.
- **Accounts and fees (no token).** `MsgRegister` is signed by a registrar and creates
  the account holding the ML-DSA pubkey. The registrar also issues a pseudonymous
  unique-human ID, which the attester rules use. v1 registrar: Omarchy.Fans identity
  (GitHub OAuth, account age ≥ N days), which is a named centralization point.
  Governance can add more registrars. Registrar-mediated **key rotation and recovery**
  means a lost keyring doesn't lose a rating.
- **Anti-spam** (zero fees means garbage costs an attacker nothing):
  - per-account, per-message-type quotas in the ante handler, with `MsgProveRun` weighted
    heavily;
  - a real block max-gas;
  - a cap on proofs per block;
  - gas proportional to proof size.
- **Proofs in consensus:**
  - Raise `max_tx_bytes` (default 1 MB) and the block `max_bytes` deliberately, and
    check the p2p message limits.
  - Proof bytes live in block history forever, which is a ROM-leak surface. Plan
    pruning, and M3 decides whether this is acceptable.
  - The verifier is consensus code, so wrap it in panic recovery. Pin the verifier
    version per season; fixes ship as coordinated upgrades.

### Modules
| Module | Holds | Messages / logic |
|---|---|---|
| `x/catalog` | titles; romsets (per-file size, CRC32, SHA-1 from MAME DATs, canonical hash order); **rating pools**; score RAM map; provable flag | governance only |
| `x/season` | window; pinned core version, guest vkey, verifier version and **canonical machine config** per title; rating params | governance |
| `x/score` | runs, tiers, attester pool | `MsgCommitRun`, `MsgRevealRun`, `MsgAttestRun` (assigned attesters, challenge frame), `MsgChallengeRun`; demotion when a log isn't available |
| `x/proof` | vkey registry; proof hash only | `MsgProveRun` → verify + every public-input check in §4 → verified execution |
| `x/match` | results | `MsgSettleMatch` (needs a matchmaker ticket), `MsgClaimDisconnect`, `MsgDispute` |
| `x/rating` | Glicko-2 per **rating pool** per season | weekly period, **processed in paged batches across blocks**. **Fixed point:** exp, ln and sqrt implemented, with a capped Illinois iteration for σ′ (`LegacyDec` has no exp/ln; evaluate `math.Dec`). Test vector: Glickman's example (1500/200 → 1464.06/151.52, σ 0.05999) within a stated tolerance |
| `x/tournament` (M6) | brackets, check-in | free entry only |

**Rating pools.** Rate per title, and split only where revisions really play
differently. Romsets map to pools in the catalog, which keeps the thin early player
base together. This refines the README's "keyed on romset hash" line: runs and proofs
bind to the romset hash, and ratings bind to the pool.

**Load.** A generous year-1 is ~5k weekly players and ~50k matches/week, about
0.1 tx/s. That's trivial for CometBFT. The binding constraints are proof tx size and
verification time.

### Money: not at launch
- **No speculative token**, because of securities exposure.
- **No paid-entry prizes** until a legal review. Prizes are sponsor-funded.
- **The FBNeo trap.** Ranked FBNeo play must never *require* a paid tier, so relays
  need a free tier and every paid extra has to be core-agnostic.

## 7. Client plugin (this repo)

```
manifest.json          id fans.omarchy.arcade; kinds panel + bar-widget
ArcadePanel.qml        library · lobby/queue · profile · runs · settings
BarWidget.qml          chip + update-alert dot (bar-widget pattern)
bin/arcade             bash CLI → runner; update-check|update-dismiss|update-run
lib/update.sh          COPY ~/Work/omarchy-plugin-browser/lib/update.sh; edit only
                       the "this plugin" block: UPD_ID=fans.omarchy.arcade,
                       UPD_REPO=OmarchyFans/omarchy-fans-arcade, UPD_BRANCH=main,
                       UPD_SLUG=omarchy-arcade, UPD_KEEP_LOADED=0,
                       UPD_BUILT_STAMP=<runner dir>/.built-from
install.sh             fetch the pinned release runner binary, sha256-verified;
                       else `cargo build --locked`; never elevates
uninstall.sh           removes runner + cache; keeps ROMs and keys unless asked
tests/run.sh           pattern from ~/Work/omarchy-feedback/tests/run.sh (+ stubs/)
catalog/catalog.json   + catalog.schema.json (never named manifest.json)
runner/                Cargo workspace: arcade-runner, arcade-libretro, arcade-net,
                       arcade-log, arcade-core (no_std), arcade-chain-client
prover/                zkVM host + guest (guest = arcade-core)
tools/dat-import       MAME DAT/XML → catalog romset hashes
tools/oracle-compare   maintainer-local only: MAME Lua injects an .arclog and dumps a
                       RAM hash per frame; diff against arcade-core
```

**The `.arclog` format.**
- Header: `{title, romset_hash, machine_config_hash, core_ver, rate_hz, players,
  frame_count}`. There is **no seed**.
- Body: one packed input entry per frame, compressed with zstd.
- Content-addressed; that hash goes on-chain. It contains no ROM data.

**Keys.** An ML-DSA key is created on the first ranked action and stored in libsecret,
with export and backup. Casual and local play never need a key.

**ROM import.** Scan a chosen folder, hash every file inside each archive, and show
each title as playable, wrong revision, or missing files. Nothing leaves the machine.

**Content on an empty install.** One click fetches the mamedev free titles *from
mamedev.org* (their permitted channel), plus allowlisted FOSS and homebrew titles. Each
comes with a recorded source and license.

## 8. Milestones

| # | Deliverable | Exit criteria |
|---|---|---|
| **M0** Foundations | plugin skeleton + update alert, runner stub, catalog schema + dat-import, CI; **spike: ML-DSA accounts in the Cosmos SDK** | `omarchy plugin validate` passes; update alert works against `file://` fixtures; spike report |
| **M1** Local play | **week 1: Hyprland runtime-rules spike**; libretro host, SDL3, session wrapper, ROM import, couch co-op, latency-test | Galaga plays correctly rotated; latency within budget; the screen never locks mid-game |
| **M2** arcade-core | Z80 + Pac-Man board + the mamedev-free board; `.arclog`; determinism contract in CI; idle-loop fast-forward | our test ROMs pass; native = executor per-frame hashes; oracle-compare matches MAME for a full run (maintainer-local) |
| **M3** ZK gate | zkVM bake-off; **our Cosmos-embeddable compressed-STARK verifier**; a real run proven in segments | written go/no-go with measured cycles, hours, $, proof size and the ZK property, **published before M4** |
| **M4** Chain testnet | arcade-chain repo; PoA + ML-DSA; registrar; x/catalog, x/season, x/score, x/proof; indexer; boards in the panel | commit → reveal → assigned attest → challenge → prove, all passing on testnet; dedup rule tested |
| **M5** Netplay | GGRS/WebRTC, matchmaker + tickets, TURN, ping gates, casual queue, x/match, x/rating, spectate | SyncTest green; two machines under netem 100 ms/1% loss don't hitch; peer-identity checks enforced; Glicko vector passes |
| **M6** Community | portal (reuses cloud auth), seasons, live-witnessed runs, TAS boards, tournaments, achievements, mainnet | first season runs; marketplace submission with a maintainer note on network use |

M1–M2 need no server. The chain arrives with score attack, the mode that most needs
cryptographic trust.

## 9. Risks & gates

| Risk | Likelihood | Mitigation / gate |
|---|---|---|
| No zkVM passes raw-STARK + ZK + embeddable verifier | medium–high | M3 gate; fall back to attestation + challenges, and scope the PQ claim |
| ROM fragments leak through non-ZK proofs or block history | medium | M3 criterion; pruning; legal sign-off, or don't publish proofs |
| Private-GPU proving counts as distribution | unknown | legal review before verified execution ships |
| TAS logs pass as human play | certain, if left unaddressed | "verified execution" wording, a TAS category, live-witnessed prizes |
| Record theft or attestation collusion | high, if left unaddressed | commit–reveal, assigned attesters, challenge frames, unique-human IDs |
| arcade-core accuracy drifts from MAME | medium | oracle-compare per board before it's marked provable |
| Too few players under 130 ms | high at launch | arcade nights, friends queue, async duels |
| libretro cores diverge between peers | per title | peer-identity checks, state sync after boot, SyncTest, quirk flags |
| Hyprland rules can't be set at runtime | low–medium | M1 week-1 spike; fall back to an opt-in snippet |
| PoA read as "not decentralized" | medium | independent operators at genesis; a published path to widen the set |

## 10. Verification

- **Plugin:**
  - `omarchy plugin validate .` and `tests/run.sh`;
  - the update alert, via `OMARCHY_PLUGIN_UPDATE_RAW=file://…`;
  - a throwaway `quickshell -p` harness (its windows appear on the desktop).

  Deploy to an installed copy once per version, never while the screen is locked.
- **Determinism:** the same `.arclog` gives identical per-frame hashes natively and in
  the zkVM executor, on 32- and 64-bit targets.
- **Accuracy:** oracle-compare against MAME, locally with maintainer-owned dumps. CI uses
  our assembled test ROMs plus downloaded Z80 test suites, hash-pinned and not vendored.
- **Netcode:** SyncTest in CI; two machines under `tc netem` (50/100/150 ms, 1–3% loss,
  jitter); zero desyncs.
- **Latency:** latency-test with 240 fps video, before and after tearing.
- **Chain:**
  - module unit tests and the Glickman vector;
  - a localnet e2e script covering commit/reveal/attest/challenge/prove, and
    settle/dispute/disconnect;
  - adversarial tests: a resubmitted log, a mismatched DIP config, a hacked romset, a
    wrong vkey, an oversized or garbage proof, a lazy attester;
  - ML-DSA bandwidth on the testnet.

## Open decisions

1. **PoA with no token** instead of a PoS staking token. It keeps things legally simple
   and play free, at the cost of weaker decentralization at launch.
2. **Score attack before netplay.** Netplay-first is possible, but then the chain
   launches without the mode that needs it most.
3. **Own provable core** for a small set of titles. FBNeo/MAME titles can't be proven for
   licensing reasons, not for lack of effort.

## Revisit as it grows
- PoS or shared security after a year of mainnet.
- Prover markets, once there's a legal route for ROM-private proving.
- 68000 boards (CPS, NeoGeo) in arcade-core, if proving costs keep falling.
- Splitting the portal and indexer into their own repo.
