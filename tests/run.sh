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
fi

# ---------------------------------------------------------------------------
if want cli; then
  echo "== cli: bin/arcade"
  ROMS="$HOME/Games/arcade"

  reset_log
  ARCADE_MAME=/nonexistent expect_exit 3 "no MAME: exits 3" -- "$A" play pacman
  logged "needs MAME" && logged "pacman -S mame" || tfail "no-MAME notification"
  pass "no MAME: notification says how to install it"

  expect_exit 4 "no ROM folder: exits 4" -- "$A" play galaga
  mkdir -p "$ROMS"
  reset_log
  expect_exit 5 "no ROM zip: exits 5" -- "$A" play ssf2
  logged "ssf2.zip" && logged "qsound.zip" && logged "0.289" || tfail "missing-ROM notification"
  pass "missing ROM: names the zip, the device ROM and the MAME version"

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
  rm -f "$XDG_CONFIG_HOME/omarchy-arcade/config.json"

  "$A" list >"$T/list"
  grep -q '^brick .*ready' "$T/list" && grep -q '^galaga .*ROM found' "$T/list" && grep -q '^ssf2 .*add your own ssf2.zip' "$T/list" || { cat "$T/list"; tfail "list"; }
  pass "list shows what is ready"

  reset_log
  expect_exit 0 "brick launches" -- "$A" play brick
  logged "record -n -p $ROOT/game/shell.qml" || tfail "quickshell argv"
  [[ -d $XDG_STATE_HOME/omarchy-arcade ]] || tfail "state folder for the high score"
  pass "brick: one instance of the game's own Quickshell config"

  expect_exit 2 "unknown game: exits 2" -- "$A" play nope
  expect_exit 2 "unknown command: exits 2" -- "$A" frobnicate
  "$A" help | grep -q 'arcade play brick' || tfail "help"
  pass "help"
fi

# ---------------------------------------------------------------------------
if want install; then
  echo "== install / uninstall"
  "$ROOT/install.sh" >"$T/inst" || tfail "install.sh"
  grep -q 'Brick Blitz' "$T/inst" && [[ -d $XDG_CONFIG_HOME/omarchy-arcade && -d $HOME/Games/arcade ]] || tfail "install.sh output or folders"
  pass "install.sh creates Arcade's folders and reports"
  ARCADE_MAME=/nonexistent "$ROOT/install.sh" | grep -q 'pacman -S mame' || tfail "install.sh without MAME"
  pass "install.sh explains MAME when it is missing"
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
  echo "== game: Brick Blitz rules, headless"
  if [[ ! -x /usr/bin/quickshell ]]; then
    skip "quickshell is not installed here"
  else
    G="$T/game"; mkdir -p "$G"
    cp "$ROOT"/game/*.qml "$ROOT"/game/*.js "$ROOT/tests/game_test.qml" "$G/"
    rm -f "$G/shell.qml"          # the test brings its own ShellRoot
    QT_QPA_PLATFORM=offscreen ARCADE_TEST_OUT="$T/game.json" timeout 30 /usr/bin/quickshell -p "$G/game_test.qml" >/dev/null 2>&1 || true
    [[ -s $T/game.json ]] || tfail "the game test wrote no result (a QML error? see: quickshell log -p $G/game_test.qml)"
    failed=$(jq -r '.failed | length' "$T/game.json")
    passed=$(jq -r '.passed' "$T/game.json")
    (( failed == 0 )) || { jq -r '.failed[]' "$T/game.json" | sed 's/^/       /'; tfail "$failed game rule(s) failed"; }
    pass "$passed game rules"
  fi
fi

echo "all tests passed"
