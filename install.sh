#!/bin/bash
#
# install.sh — optional setup for Arcade. `omarchy plugin add` is all Arcade
# needs; this only creates Arcade's own folders ahead of time and tells you
# what is ready. It installs no packages, touches no system files and
# downloads nothing. Safe to run again.
set -euo pipefail
export PATH="/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin"

DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-arcade"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-arcade"
MAME="${ARCADE_MAME:-/usr/bin/mame}"

mkdir -p "$CONFIG_DIR" "$STATE_DIR"
ROMS=$(/usr/bin/bash "$DIR/bin/arcade" rom-dir)

echo "Arcade is ready."
echo "  Brick Blitz  plays now: click the Arcade chip in your bar."
if [[ -x $MAME ]]; then
  echo "  MAME         found: $("$MAME" -version 2>/dev/null | head -n1)"
else
  echo "  MAME         not installed. For Pac-Man, Galaga and Super Street Fighter II,"
  echo "               install it with your package manager: pacman -S mame"
fi
echo "  ROM folder   $ROMS"
echo "               Put your own pacman.zip, galaga.zip and ssf2.zip here."
echo "               Arcade never downloads games. Run 'arcade list' to see what is ready."
