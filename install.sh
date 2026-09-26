#!/bin/bash
#
# install.sh — optional setup for Arcade. `omarchy plugin add` is all Arcade
# needs; this creates Arcade's own folders ahead of time and, when run in a
# terminal, installs MAME for the arcade games (Omarchy's own omarchy-pkg-add;
# your password may be asked). Without a terminal it installs nothing: MAME then
# installs itself the first time you pick a MAME game. Safe to run again.
set -euo pipefail
export PATH="/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin"

DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-arcade"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-arcade"
MAME="${ARCADE_MAME:-/usr/bin/mame}"

interactive() { # same rule as bin/arcade; ARCADE_INTERACTIVE=0|1 is for the tests
  case "${ARCADE_INTERACTIVE:-}" in 1) return 0 ;; 0) return 1 ;; esac
  [[ -t 0 && -t 1 ]]
}

mkdir -p "$CONFIG_DIR" "$STATE_DIR"
ROMS=$(/usr/bin/bash "$DIR/bin/arcade" rom-dir)

if [[ ! -x $MAME ]] && interactive; then
  /usr/bin/bash "$DIR/bin/arcade" install-mame || true
  echo
fi

echo "Arcade is ready."
echo "  Brick Blitz  plays now: click the Arcade chip in your bar."
if [[ -x $MAME ]]; then
  echo "  MAME         found: $("$MAME" -version 2>/dev/null | head -n1)"
else
  echo "  MAME         installs automatically the first time you pick Pac-Man, Galaga"
  echo "               or Super Street Fighter II (or run: arcade install-mame)."
fi
echo "  ROM folder   $ROMS"
echo "               Put your own pacman.zip, galaga.zip and ssf2.zip here."
echo "               Arcade never downloads games. Run 'arcade list' to see what is ready."
