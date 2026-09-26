# Built-in games: the contract

Every built-in game lives in its own folder, `games/<id>/`, and needs nothing
outside it. `bin/arcade`, the bar menu and the test suite discover games by their
`game.json`, so adding a game means adding a folder and a test file. You never
edit a shared file.

`games/brick/` (Brick Blitz) is the reference implementation. When this document
says "as Brick Blitz does", read that code.

## Layout

```
games/<id>/
  game.json        what the menu and CLI show (below)
  shell.qml        the window: ShellRoot + FloatingWindow + theme + high score
  Game.qml         the whole game: state, rules, physics, drawing, input
  *.js             data and pure helpers (`.pragma library`), e.g. levels.js
tests/<id>_test.qml   the headless rules test (below)
```

- `<id>` is lowercase letters, digits and dashes, and matches the folder name.
- **Never** name any file `manifest.json`. The marketplace reserves that name.
- No symlinks, no binaries, no downloaded assets. Everything is QML/JS written for
  this repository. Draw with Rectangles, Text, Canvas or Shape; there are no image
  files.
- Don't touch anything outside `games/<id>/` and `tests/<id>_test.qml`.

### game.json

```json
{
  "id": "brick",
  "title": "Brick Blitz",
  "note": "built in",
  "order": 10,
  "genre": "brick-breaker",
  "description": "One sentence a player understands."
}
```

`order` sorts the menu (Brick Blitz is 10; use 20, 30, …). The `note` shows next to
the title in the menu; keep it to three words or fewer.

## shell.qml (the window)

Copy `games/brick/shell.qml` and change only:
- the score file name, `<id>.json`;
- the window title;
- the `Game { }` block.

It already does these things right; keep them:
- It **runs as its own Quickshell process**, never inside the bar. `bin/arcade`
  starts it with `quickshell -n -p games/<id>/shell.qml`.
- It reads the Omarchy theme from
  `$XDG_STATE_HOME/omarchy/current/theme/colors.toml` (flat `key = "#rrggbb"`
  lines).
- It saves the high score with `FileView` + **`blockWrites: true`**, debounced
  after the score stops climbing and flushed on game over and on quit.
- **Closing the window quits the process** (`onVisibleChanged`). Quickshell
  doesn't exit when its last window closes.

## Game.qml: the engine rules

These rules exist because each one broke something in Brick Blitz.

1. **A fixed field, scaled.** The game plays in a fixed logical field (Brick Blitz is
   800×600) that is scaled uniformly to fit the window. Physics never depend on the
   window size.
2. **Fixed physics steps.** A `FrameAnimation` drives `step(dt)` in small fixed
   substeps (Brick Blitz uses 1/240 s), with `dt` capped at 1/30 s.
3. **No Timers in the game logic.** Countdowns (power-up durations, spawn delays,
   respawn pauses, level transitions, combo windows, AI decisions) are numbers
   decremented inside `step(dt)`. The headless test drives `step()` by hand and
   Timers never fire there. (A banner that only fades text is the one exception.)
4. **Seeded randomness.** Keep a `seed` property and a small PRNG such as
   mulberry32. `Math.random()` appears nowhere in game logic. Tests set the seed;
   live play seeds from the clock.
5. **Draw without freezing.** For moving things kept in JS arrays (enemies, shots,
   particles):
   - Mutate them in place during `step()`, then replace the array **once per frame**
     (`things = things.slice()`), never per substep.
   - Delegates must read the array through an accessor function,
     `x: game.thingAt(index).x`, where `thingAt(i)` returns `things[i] || offField`.
   - **Never** hold the element in a delegate property
     (`property var t: game.things[index]`). Re-assigning the same object signals no
     change, so the drawing freezes. This happened in Brick Blitz and the logic tests
     did not catch it.
   - Grid-shaped state (bricks, tiles, board cells) can use a `ListModel` with
     `setProperty`.
6. **Controls.**
   - Arrows or WASD move, and Space or Enter is the main action.
   - **P** pauses, **Esc** quits (a `quitRequested()` signal), and **Enter** starts
     over after a game over.
   - `lostFocus()` pauses and clears every held-key flag; wire it to
     `Qt.application.onStateChanged`, as Brick Blitz does. Handle `isAutoRepeat`
     deliberately.
   - Two-player games put player 2 on the arrows plus right Ctrl/Shift/Enter and
     player 1 on WASD plus F/G/H, and offer "1 player vs CPU".
7. **Theme colors.**
   - Use `color(key, fallback)` with the keys in the theme's `colors.toml`:
     background, dark_background, lighter_background, foreground, bright_foreground,
     accent, red, orange, yellow, green, cyan, blue, magenta.
   - The game must look right in any theme and must not hard-code one palette.
8. **HUD and messages** as Brick Blitz does: score, high score, level/round, lives;
   a start prompt, PAUSED and GAME OVER with a backdrop.
9. **Signals for the host.** `quitRequested()` and `newHighScore(int)` exist. Also
   expose `highScore`, `score`, `phase` (at least serve/ready, play, paused, over)
   and `beatHigh` (true only when this game went past the old best, not on a tie).
10. **No sound** (Brick Blitz has none) and no network.

## tests/<id>_test.qml: the rules test

- Copy the shape of `tests/brick_test.qml`: a `ShellRoot`, a hidden
  `FloatingWindow` containing `Game { id: g }`, and one `Timer` that runs `tests()`,
  writes `{"passed": n, "failed": [..]}` to `$ARCADE_TEST_OUT`, then quits.
- `tests/run.sh` copies `games/<id>/*` plus the test into one temp folder (without
  `shell.qml`) and runs it with `QT_QPA_PLATFORM=offscreen quickshell -p`. Import
  your files by their plain names, e.g. `import "levels.js" as Levels`. Quickshell
  refuses imports from outside the folder.
- **At least 20 rules**, and they must test real behaviour:
  - scoring;
  - win and lose conditions;
  - every power-up or special move;
  - AI decisions (with a fixed seed);
  - edge cases (walls, wrap-around, simultaneous events);
  - pause and `lostFocus()`;
  - new game resets everything;
  - the high-score tie rule;
  - **at least two render rules**: after `publish()`, a drawn delegate
    (`someView.itemAt(i)`) is where its model says, and moves when the model moves.
- **Every rule must be able to fail.** No `check(name, true)`.
- Run your game with:
  ```sh
  tests/run.sh game
  ```
  It runs every game's rules. Your game passes when it reports `<id>: N game rules`
  with no FAIL.
- **Never open a window on the desktop.** Tests run offscreen only. The maintainer
  does the live check.

## Legal: our games are our own

Genre mechanics are free to use: a maze with chasers, falling pieces, match-three,
a formation shooter, a 1-on-1 fighter. A game's **expression** is not: its name,
characters, art, sounds, level layouts and distinctive look. Owners enforce this.

- *Tetris Holding v. Xio* (2012): a clone lost for copying Tetris's **look**, even
  with its own code.
- *Atari v. Philips* (1982): K.C. Munchkin lost over its Pac-Man-like characters.

Rules:
- **An original name.** Before using it, check that no known game (web search) and
  no marketplace plugin (`catalog.json`) already uses it. Say what you checked in
  your report.
- **No protected names, characters or signature moves** anywhere in the game's files
  or UI. `tests/run.sh` greps for many of them and fails the build.
- **Original characters and art.**
- **Original level or maze layouts.** Never trace a classic one.
- **Distinct presentation from the famous original:** different proportions,
  different piece colors and palette, different signature features. The per-genre
  notes below are the minimum.

### Per-genre minimums

- **Maze chase:**
  - the hero is not yellow and not a pie/wedge with a mouth;
  - chasers are not dome-with-wavy-hem "ghosts" and don't use a red/pink/cyan/orange
    quartet;
  - power items are not big blinking pellets;
  - no "ghosts", "power pellets" or "waka".
- **Falling blocks:**
  - no 10×20 well, no standard seven-tetromino set with its standard colors, no ghost
    or shadow piece in the classic style, no "T-spin" naming;
  - use a different well (e.g. 12 wide), a different piece family (e.g. pentominoes
    or trominoes, or your own shapes), and your own clear/score mechanic twist.
- **Match-three:**
  - no candy, sweets or jelly theme, no "Saga" or "Crush" in the name;
  - an original tile theme (e.g. circuit components or gems of your own design) and
    at least one mechanic of your own.
- **Formation shooter:**
  - no bug-like enemies swooping in the classic look;
  - no tractor-beam "capture your ship, win it back" mechanic presented the classic
    way;
  - original enemy designs, formations and patterns.
- **1-on-1 fighter:**
  - original fighters, names and moves, with no quarter-circle fireball or
    dragon-punch naming or visuals;
  - health bars and rounds are fine.
- **Vector space shooter:**
  - no "Asteroids" naming;
  - original hazards (not only splitting rocks) and an original ship.
- **Road or river crossing:**
  - no frog;
  - original hero, lanes and hazards.
- **Paddle or air-hockey duel:** fine as a genre; use an original name and look.

## Scope for one game

- **A complete, polished v1:**
  - playable start to game over;
  - a level or difficulty curve;
  - at least one special mechanic that makes it more than a clone;
  - smooth at 60 fps on a laptop.
- **Keep Game.qml readable:** helpers in `.js` files, comments that explain the
  rules.
- **When you finish, report:**
  - the name and how you checked it;
  - the files;
  - the rules count and the test result;
  - anything you could not verify.
