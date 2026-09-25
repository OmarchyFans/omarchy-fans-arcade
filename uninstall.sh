#!/bin/bash
#
# uninstall.sh — remove what Arcade created outside its plugin folder:
#   ~/.config/omarchy-arcade   settings
#   ~/.cache/omarchy-arcade    the update-check cache
#   ~/.local/state/omarchy-arcade/mame   MAME's settings files for Arcade launches
#
# Your Brick Blitz high score stays unless you pass --purge. Your ROM folder is
# never touched: those are your files. Remove the plugin itself with
#   omarchy plugin remove fans.omarchy.arcade
set -euo pipefail
export PATH="/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-arcade"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-arcade"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-arcade"

purge=0
case "${1:-}" in
  --purge) purge=1 ;;
  "") ;;
  *) echo "usage: uninstall.sh [--purge]" >&2; exit 2 ;;
esac

rm -rf -- "$CONFIG_DIR" "$CACHE_DIR" "$STATE_DIR/mame"
if (( purge )); then
  rm -rf -- "$STATE_DIR"
  echo "Removed Arcade's settings, cache and high scores."
else
  rmdir -- "$STATE_DIR" 2>/dev/null || true
  echo "Removed Arcade's settings and cache. High scores kept (uninstall.sh --purge removes them)."
fi
echo "Your ROM files were not touched."
