#!/bin/bash
# Tests for Arcade. Everything runs under throwaway XDG dirs with a stub MAME,
# a stub notify-send and a stub quickshell; nothing touches the real session.
#   tests/run.sh [group...]   groups: lint repo cli install update game (default: all)
# The game group needs /usr/bin/quickshell (it runs Brick Blitz's rules headless);
# it is skipped, and says so, where quickshell is missing (CI).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

export HOME="$T/home" XDG_CONFIG_HOME="$T/config" XDG_STATE_HOME="$T/state" XDG_CACHE_HOME="$T/cache"
export STUB_LOG="$T/stub.log"
export ARCADE_MAME="$ROOT/tests/stubs/mame" ARCADE_NOTIFY="$ROOT/tests/stubs/record" ARCADE_QUICKSHELL="$ROOT/tests/stubs/record"
export ARCADE_PKG_ADD="$ROOT/tests/stubs/pkg-add" ARCADE_LAUNCH_TUI="$ROOT/tests/stubs/record" ARCADE_INTERACTIVE=0
export ARCADE_OPEN="$ROOT/tests/stubs/record"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
A="$ROOT/bin/arcade"

pass() { echo "  ok   $*"; }
tfail() { echo "  FAIL $*"; [[ -s $STUB_LOG ]] && { echo "--- stub log"; tail -n 20 "$STUB_LOG"; }; exit 1; }
skip() { echo "  skip $*"; }
reset_log() { : >"$STUB_LOG"; }
logged() { grep -qF -- "$1" "$STUB_LOG"; }
expect_exit() { # expect_exit CODE NAME -- command...
  local want=$1 name=$2 got=0; shift 3
  "$@" >"$T/out" 2>&1 || got=$?
  [[ $got == "$want" ]] || { cat "$T/out"; tfail "$name: exit $got, want $want"; }
  pass "$name"
}

GROUPS_ALL=(lint repo cli install update game)
SELECTED=("$@"); (( ${#SELECTED[@]} )) || SELECTED=("${GROUPS_ALL[@]}")
want() { local g; for g in "${SELECTED[@]}"; do [[ $g == "$1" ]] && return 0; done; return 1; }

# ---------------------------------------------------------------------------
if want lint; then
  echo "== lint"
  shellcheck -S warning -x "$A" "$ROOT/lib/update.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" \
    "$ROOT/tests/run.sh" "$ROOT"/tests/stubs/* || tfail "shellcheck"
  pass "shellcheck (warning and up)"
  for f in "$A" "$ROOT/lib/update.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT"/tests/stubs/*; do
    [[ -x $f ]] || tfail "not executable: ${f#"$ROOT"/}"
  done
  pass "scripts are executable"
fi

# ---------------------------------------------------------------------------
if want repo; then
  echo "== repo: manifest and marketplace rules"
  M="$ROOT/manifest.json"
  jq -e . "$M" >/dev/null || tfail "manifest.json is not JSON"
  [[ $(jq -r .id "$M") == fans.omarchy.arcade ]] || tfail "manifest id"
  [[ $(jq -r '.kinds | join(",")' "$M") == bar-widget ]] || tfail "manifest kinds"
  [[ -f $ROOT/$(jq -r .entryPoints.barWidget "$M") ]] || tfail "bar widget entry point is missing"
  pass "manifest id, kind and entry point"
  v=$(jq -r .version "$M")
  top=$(grep -m1 -E '^## [0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CHANGELOG.md" | sed 's/^## //')
  [[ $v == "$top" ]] || tfail "manifest version $v but CHANGELOG's newest section is $top"
  pass "manifest version matches CHANGELOG ($v)"
  # The marketplace validator counts every manifest.json at the root or one folder deep.
  n=$(find "$ROOT" -maxdepth 2 -name manifest.json -not -path "$ROOT/.claude/*" | wc -l)
  [[ $n == 1 ]] || tfail "$n manifest.json files within two levels; the marketplace allows one"
  pass "one manifest.json"
  [[ -z $(find "$ROOT" -type l -not -path "$ROOT/.claude/*" -not -path "$ROOT/.git/*" | head -n1) ]] || tfail "the repo contains a symlink"
  pass "no symlinks"
  # The marketplace security baseline flags this word even in prose.
  word="su""do"
  if grep -rIl --exclude-dir=.git --exclude-dir=.claude -w "$word" "$ROOT" >"$T/hits"; then
    cat "$T/hits"; tfail "the repo mentions '$word'"
  fi
  pass "no privilege-escalation word anywhere"
  grep -qi '^## Install' "$ROOT/README.md" && grep -qi '^## Remov' "$ROOT/README.md" || tfail "README needs Install and Removal sections"
  pass "README has install and removal"
  # Bullets must be one plain line: the update popup shows only a bullet's first line.
  awk -v v="$v" '$0 == "## " v {f=1; next} /^## /{f=0} f && /^[-*] /{n++} f && /^  +[^ ]/{bad=1} END{exit !(n > 0 && !bad)}' "$ROOT/CHANGELOG.md" \
    || tfail "CHANGELOG $v needs single-line bullets"
  pass "CHANGELOG $v has single-line bullets"
  # Built-in games: a complete game.json, a shell.qml, and their own rules test.
  for gj in "$ROOT"/games/*/game.json; do
    gdir=$(dirname "$gj"); gid=$(basename "$gdir")
    jq -e --arg id "$gid" '(.id == $id) and (.title | type == "string" and length > 0) and (.note | type == "string")
        and (.order | type == "number") and (.genre | type == "string") and (.description | type == "string")' "$gj" >/dev/null \
      || tfail "games/$gid/game.json: needs id (= folder), title, note, order, genre, description"
    [[ -f $gdir/shell.qml && -f $ROOT/tests/${gid}_test.qml ]] || tfail "games/$gid needs shell.qml and tests/${gid}_test.qml"
  done
  pass "every built-in game has a complete game.json, a shell.qml and a rules test"
  # Our games are our own: no protected game names, characters or signature
  # moves anywhere in a game's files (docs/GAMES.md, "Legal").
  marks='pac-?man|puck-?man|galaga|galaxian|tetris|tetromino|candy ?crush|street ?fighter|hadou?ken|shoryuken|sonic ?boom|arkanoid|space ?invaders|asteroids|frogger|centipede|donkey ?kong|blinky|pinky|inky|clyde|chun-?li|m\.? ?bison'
  if grep -rIliE "$marks" "$ROOT/games" >"$T/marks"; then
    grep -rIniE "$marks" "$ROOT/games" | head -n 10
    tfail "a built-in game uses a protected name (see docs/GAMES.md)"
  fi
  pass "no protected game names inside games/"
fi

# ---------------------------------------------------------------------------
if want cli; then
  echo "== cli: bin/arcade"
  ROMS="$HOME/Games/arcade"

  # MAME installs itself on first play.
  NOMAME="$T/bin/mame"                       # where the stub "installs" it
  reset_log
  ARCADE_MAME=$NOMAME expect_exit 0 "no MAME, from the bar: opens the installer" -- "$A" play pacman
  wait_for_log() { local n=30; while (( n-- > 0 )); do logged "$1" && return 0; sleep 0.1; done; return 1; }
  wait_for_log "record --app-id=TUI.float /usr/bin/bash $A install-mame --then pacman" || tfail "installer terminal argv"
  logged "Installing MAME first" || tfail "installer notification"
  pass "no MAME, from the bar: a terminal runs install-mame --then pacman"

  reset_log
  ARCADE_MAME=$NOMAME STUB_PKG_INSTALL_TO=$NOMAME expect_exit 0 "install-mame installs MAME" -- "$A" install-mame
  logged "pkg-add mame" && [[ -x $NOMAME ]] || tfail "install-mame should run omarchy-pkg-add mame"
  pass "install-mame runs omarchy-pkg-add mame"
  ARCADE_MAME=$NOMAME expect_exit 0 "install-mame when MAME is there" -- "$A" install-mame
  grep -q 'already installed' "$T/out" || tfail "install-mame should say MAME is already there"
  rm -f "$NOMAME"

  reset_log
  ARCADE_MAME=$NOMAME STUB_PKG_FAIL=1 expect_exit 1 "install-mame: a failed install exits 1" -- "$A" install-mame --then galaga
  grep -q 'did not install' "$T/out" && ! logged "play galaga" || tfail "failed install must not start the game"
  pass "a failed install says so and starts nothing"

  reset_log
  ARCADE_MAME=$NOMAME STUB_PKG_INSTALL_TO=$NOMAME expect_exit 0 "install-mame --then: installs" -- "$A" install-mame --then galaga
  # The game starts detached; with no ROM folder yet, it says so.
  wait_for_log "Galaga: add your ROM" || tfail "install-mame --then should start the game"
  pass "install-mame --then starts the picked game on its own"
  rm -f "$NOMAME"
  expect_exit 2 "install-mame --then an unknown game: exits 2" -- "$A" install-mame --then nope

  reset_log
  rm -rf "$ROMS"
  ARCADE_MAME=$NOMAME ARCADE_INTERACTIVE=1 STUB_PKG_INSTALL_TO=$NOMAME expect_exit 4 "no MAME, at a terminal: installs inline, then checks ROMs" -- "$A" play galaga
  logged "pkg-add mame" && [[ -x $NOMAME ]] || tfail "inline install"
  pass "no MAME, at a terminal: installs inline and carries on"
  rm -f "$NOMAME"

  reset_log
  ARCADE_MAME=$NOMAME ARCADE_LAUNCH_TUI=/nonexistent expect_exit 3 "no MAME, no terminal launcher: exits 3" -- "$A" play pacman
  logged "arcade install-mame" || tfail "fallback notification should name arcade install-mame"
  pass "no MAME and no launcher: notification names arcade install-mame"

  rm -rf "$ROMS"
  reset_log
  expect_exit 4 "no ROM folder: exits 4" -- "$A" play galaga
  [[ -d $ROMS ]] && logged "record $ROMS" || tfail "no ROM folder: it should be created and opened"
  pass "no ROM folder, from the bar: creates it and opens it"
  reset_log
  expect_exit 5 "no ROM zip: exits 5" -- "$A" play ssf2
  logged "ssf2.zip" && logged "qsound.zip" && logged "0.289" && logged "can't include" || tfail "missing-ROM notification"
  logged "record $ROMS" || tfail "missing ROM, from the bar: the ROM folder should open"
  pass "missing ROM, from the bar: opens the ROM folder and names the zip, device ROM and MAME version"
  reset_log
  ARCADE_INTERACTIVE=1 expect_exit 5 "missing ROM at a terminal: exits 5" -- "$A" play ssf2
  ! logged "record $ROMS" || tfail "at a terminal the ROM folder should not pop open"
  pass "missing ROM at a terminal: says so without opening windows"

  : >"$ROMS/galaga.zip"
  reset_log
  STUB_MAME_VERIFY=bad expect_exit 6 "bad ROM: exits 6" -- "$A" play galaga
  logged "NOT FOUND" || tfail "bad-ROM notification should quote MAME"
  pass "bad ROM: notification quotes MAME's check"

  reset_log
  expect_exit 0 "good ROM launches" -- "$A" play galaga
  logged "argv=-rompath $ROMS -skip_gameinfo galaga" || tfail "MAME argv"
  logged "cwd=$XDG_STATE_HOME/omarchy-arcade/mame argv=-rompath" || tfail "MAME must run in Arcade's state folder"
  pass "good ROM: MAME gets the ROM folder and runs from Arcade's state folder"

  # A merged set keeps Pac-Man inside puckman.zip.
  : >"$ROMS/puckman.zip"
  reset_log
  expect_exit 0 "pacman from a merged puckman.zip" -- "$A" play pacman
  logged "-skip_gameinfo pacman" || tfail "pacman argv"

  mkdir -p "$XDG_CONFIG_HOME/omarchy-arcade" "$HOME/elsewhere"
  printf '{"rom_dir": "~/elsewhere"}\n' >"$XDG_CONFIG_HOME/omarchy-arcade/config.json"
  [[ $("$A" rom-dir) == "$HOME/elsewhere" ]] || tfail "rom_dir from config.json with ~"
  pass "rom_dir from config.json, ~ expanded"
  # MAME runs from Arcade's state folder, so a relative rom_dir must become absolute.
  printf '{"rom_dir": "elsewhere"}\n' >"$XDG_CONFIG_HOME/omarchy-arcade/config.json"
  [[ $(cd / && "$A" rom-dir) == "$HOME/elsewhere" ]] || tfail "relative rom_dir"
  pass "relative rom_dir is taken from home, absolute"
  rm -f "$XDG_CONFIG_HOME/omarchy-arcade/config.json"

  "$A" list >"$T/list"
  grep -q '^brick .*ready' "$T/list" && grep -q '^galaga .*ROM found' "$T/list" && grep -q '^ssf2 .*add your own ssf2.zip' "$T/list" || { cat "$T/list"; tfail "list"; }
  pass "list shows what is ready"
  lj=$("$A" list --json)
  state_of() { jq -r --arg id "$1" --arg k "$2" 'map(select(.id == $id))[0][$k]' <<<"$3"; }
  [[ $(state_of brick state "$lj") == ready && $(state_of galaga state "$lj") == rom-found \
     && $(state_of ssf2 state "$lj") == no-rom && $(state_of ssf2 note "$lj") == "needs ssf2.zip" ]] || { echo "$lj"; tfail "list --json"; }
  [[ $(state_of pacman state "$(ARCADE_MAME=/nonexistent "$A" list --json)") == no-mame ]] || tfail "list --json without MAME"
  pass "list --json gives the menu each game's state"

  reset_log
  expect_exit 0 "brick launches" -- "$A" play brick
  logged "record -n -p $ROOT/games/brick/shell.qml" || tfail "quickshell argv"
  [[ -d $XDG_STATE_HOME/omarchy-arcade ]] || tfail "state folder for the high score"
  pass "brick: one instance of the game's own Quickshell config"
  # Every built-in game (games/<id>/game.json) is listed and launches the same way.
  for gj in "$ROOT"/games/*/game.json; do
    gid=$(jq -r .id "$gj")
    jq -e --arg id "$gid" 'map(select(.id == $id and .kind == "builtin" and .state == "ready")) | length == 1' <<<"$("$A" list --json)" >/dev/null \
      || tfail "$gid is not listed as a ready built-in"
    reset_log
    "$A" play "$gid" >/dev/null 2>&1 || tfail "$gid did not launch"
    logged "record -n -p $ROOT/games/$gid/shell.qml" || tfail "$gid: quickshell argv"
  done
  pass "every built-in game is listed and launches ($(find "$ROOT/games" -mindepth 2 -maxdepth 2 -name game.json | wc -l))"

  expect_exit 2 "unknown game: exits 2" -- "$A" play nope
  expect_exit 2 "unknown command: exits 2" -- "$A" frobnicate
  "$A" help >"$T/help"
  grep -q 'arcade play <game>' "$T/help" && ! grep -q 'set -euo\|export PATH' "$T/help" || { cat "$T/help"; tfail "help"; }
  pass "help prints the usage and no code"
fi

# ---------------------------------------------------------------------------
if want install; then
  echo "== install / uninstall"
  "$ROOT/install.sh" >"$T/inst" || tfail "install.sh"
  grep -q 'Brick Blitz' "$T/inst" && [[ -d $XDG_CONFIG_HOME/omarchy-arcade && -d $HOME/Games/arcade ]] || tfail "install.sh output or folders"
  pass "install.sh creates Arcade's folders and reports"
  ARCADE_MAME=/nonexistent "$ROOT/install.sh" | grep -q 'installs automatically' || tfail "install.sh without MAME, no terminal"
  pass "install.sh with no terminal: says MAME installs on first play"
  reset_log
  # At a terminal (also the plugin's update terminal) install.sh asks first.
  reset_log
  echo n | ARCADE_MAME="$T/bin2/mame" STUB_PKG_INSTALL_TO="$T/bin2/mame" ARCADE_INTERACTIVE=1 "$ROOT/install.sh" >"$T/inst2" || tfail "install.sh, declined"
  ! logged "pkg-add" && grep -q 'installs automatically' "$T/inst2" || { cat "$T/inst2"; tfail "declining should skip MAME"; }
  pass "install.sh asks first, and n skips MAME"
  reset_log
  echo | STUB_PKG_FAIL=1 ARCADE_MAME="$T/bin2/mame" ARCADE_INTERACTIVE=1 "$ROOT/install.sh" >"$T/inst2" || tfail "install.sh must carry on after a cancelled install"
  ! grep -q 'Press Enter' "$T/inst2" && grep -q 'Arcade is ready' "$T/inst2" || { cat "$T/inst2"; tfail "a cancelled install should not stop install.sh"; }
  pass "a cancelled install doesn't stop install.sh"
  reset_log
  echo y | ARCADE_MAME="$T/bin2/mame" STUB_PKG_INSTALL_TO="$T/bin2/mame" ARCADE_INTERACTIVE=1 "$ROOT/install.sh" >"$T/inst2" || tfail "install.sh at a terminal"
  logged "pkg-add mame" && grep -q 'is installed' "$T/inst2" || { cat "$T/inst2"; tfail "install.sh at a terminal should install MAME"; }
  pass "install.sh at a terminal installs MAME on yes"
  mkdir -p "$XDG_STATE_HOME/omarchy-arcade/mame"
  echo '{"high": 900}' >"$XDG_STATE_HOME/omarchy-arcade/brick.json"
  : >"$HOME/Games/arcade/mine.zip"
  "$ROOT/uninstall.sh" >/dev/null
  [[ -f $XDG_STATE_HOME/omarchy-arcade/brick.json && ! -d $XDG_STATE_HOME/omarchy-arcade/mame && ! -d $XDG_CONFIG_HOME/omarchy-arcade ]] || tfail "uninstall.sh keeps the high score, removes the rest"
  [[ -f $HOME/Games/arcade/mine.zip ]] || tfail "uninstall.sh touched ROMs"
  pass "uninstall.sh keeps high scores and ROMs"
  "$ROOT/uninstall.sh" --purge >/dev/null
  [[ ! -d $XDG_STATE_HOME/omarchy-arcade && -f $HOME/Games/arcade/mine.zip ]] || tfail "uninstall.sh --purge"
  pass "uninstall.sh --purge removes high scores, still not ROMs"
fi

# ---------------------------------------------------------------------------
if want update; then
  echo "== update: lib/update.sh against file:// fixtures"
  F="$T/published"; mkdir -p "$F"
  printf '{"version": "0.9.0"}\n' >"$F/manifest.json"
  printf '# Changelog\n\n## 0.9.0\n\n- A newer thing.\n- Another newer thing.\n\n## 0.1.0\n\n- Old.\n' >"$F/CHANGELOG.md"
  export OMARCHY_PLUGIN_UPDATE_RAW="file://$F"
  out=$("$A" update-check --force)
  [[ $(jq -r .update_available <<<"$out") == true && $(jq -r .latest <<<"$out") == 0.9.0 ]] || { echo "$out"; tfail "newer version found"; }
  [[ $(jq -r '.notes | length' <<<"$out") == 2 && $(jq -r '.notes[0]' <<<"$out") == "A newer thing." ]] || { echo "$out"; tfail "changelog notes"; }
  pass "a newer published version is found, with its changelog bullets"
  "$A" update-dismiss 0.9.0
  [[ $("$A" update-check | jq -r .dismissed) == 0.9.0 ]] || tfail "dismiss"
  pass "Later remembers the dismissed version"
  printf '{"version": "%s"}\n' "$(jq -r .version "$ROOT/manifest.json")" >"$F/manifest.json"
  [[ $("$A" update-check --force | jq -r .update_available) == false ]] || tfail "same version is not an update"
  pass "the same version is not an update"
  mkdir -p "$XDG_CONFIG_HOME/omarchy-arcade"
  echo '{"update_check": false}' >"$XDG_CONFIG_HOME/omarchy-arcade/config.json"
  [[ $("$A" update-check --force | jq -r .enabled) == false ]] || tfail "opt-out"
  pass "update_check: false turns the check off"
  rm -f "$XDG_CONFIG_HOME/omarchy-arcade/config.json"
  argv=$(OMARCHY_PLUGIN_UPDATE_PRINT=1 "$A" update-run all)
  jq -e '.argv | index("terminal") and index("all")' <<<"$argv" >/dev/null || { echo "$argv"; tfail "update-run argv"; }
  pass "Update… opens the update terminal"
  unset OMARCHY_PLUGIN_UPDATE_RAW
fi

# ---------------------------------------------------------------------------
if want game; then
  echo "== game: built-in game rules, headless"
  if [[ ! -x /usr/bin/quickshell ]]; then
    skip "quickshell is not installed here"
  else
    # Each games/<id>/ has tests/<id>_test.qml. Quickshell only imports from its
    # config folder, so the game's files and its test are staged together; the
    # test brings its own ShellRoot, so the game's shell.qml is left out.
    for gj in "$ROOT"/games/*/game.json; do
      gid=$(jq -r .id "$gj")
      # ARCADE_GAME_ONLY=<id> tests one game (games being built side by side).
      [[ -n ${ARCADE_GAME_ONLY:-} && $gid != "$ARCADE_GAME_ONLY" ]] && continue
      tq="$ROOT/tests/${gid}_test.qml"
      [[ -f $tq ]] || tfail "$gid has no tests/${gid}_test.qml"
      G="$T/game-$gid"; mkdir -p "$G"
      cp -r "$ROOT/games/$gid/." "$G/"
      cp "$tq" "$G/"
      rm -f "$G/shell.qml"
      QT_QPA_PLATFORM=offscreen ARCADE_TEST_OUT="$T/$gid.json" timeout 60 /usr/bin/quickshell -p "$G/${gid}_test.qml" >/dev/null 2>&1 || true
      [[ -s $T/$gid.json ]] || tfail "$gid: the rules test wrote no result (a QML error? see: quickshell log -p $G/${gid}_test.qml)"
      failed=$(jq -r '.failed | length' "$T/$gid.json")
      passed=$(jq -r '.passed' "$T/$gid.json")
      (( failed == 0 )) || { jq -r '.failed[]' "$T/$gid.json" | sed 's/^/       /'; tfail "$gid: $failed rule(s) failed"; }
      (( passed >= 20 )) || tfail "$gid: only $passed rules; a built-in game needs at least 20"
      pass "$gid: $passed game rules"
    done
  fi
fi

echo "all tests passed"
