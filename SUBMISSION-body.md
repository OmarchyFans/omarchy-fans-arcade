### Repository URL

https://github.com/OmarchyFans/omarchy-fans-arcade

### Category

Other

### Tags

games, bar, quickshell

### Suggest a missing tag

arcade

### Maintainer notes

Arcade is an Omarchy.Fans product written by ModPunk, MIT licensed. It is a bar chip with a small game menu.

What it does:
- It plays Brick Blitz, an original brick-breaker written for Arcade in pure QML/JS: five layouts, tough bricks, and a high score saved in ~/.local/state/omarchy-arcade.
- It launches Pac-Man, Galaga and Super Street Fighter II in MAME from the user's own ROM files. Before starting a game it runs `mame -verifyroms` and names the missing or wrong file in a notification.

How it differs from Omacade and Omarchy Breakout:
- Arcade's MAME half launches the real arcade titles from files the user already owns.
- The repo's docs/ROADMAP.md describes planned online play. None of it is implemented or enabled in this version.

Arcade ships, downloads and links no ROMs or emulator binaries. MAME comes from the user's own distribution (pacman -S mame), and docs/LEGAL.md sets that out. Brick Blitz runs as its own Quickshell process (quickshell -n -p game/shell.qml), never inside omarchy-shell, so a problem in the game cannot affect the shell.

Kinds: bar-widget (BarWidget.qml).

Capabilities the baseline scan will list, all by design:
- **process-spawn:** Quickshell.execDetached with fixed absolute argv only (/usr/bin/bash <plugin>/bin/arcade play <id>) and a fixed PATH. No shell strings are ever built. bin/arcade pins PATH to root-owned dirs and calls /usr/bin/mame, /usr/bin/quickshell and /usr/bin/notify-send by absolute path.
- **network:** only the six-hourly update check (lib/update.sh, the shared Omarchy.Fans helper): one GET of this repository's manifest.json, plus CHANGELOG.md when a newer version exists, cached, with opt-out `update_check: false`. Games, scores and ROMs never leave the machine.
- **writes-user-config:** only ~/.config/omarchy-arcade, ~/.cache/omarchy-arcade and ~/.local/state/omarchy-arcade (the high score, and MAME's cfg/nvram for Arcade launches), plus the ROM folder ~/Games/arcade, which it creates when missing and never modifies.
- **installer:** install.sh is optional (plugin add is enough), only creates those folders and reports what's ready. It installs no packages, needs no root and is idempotent. uninstall.sh removes Arcade's folders, keeps the high score unless --purge, and never touches ROMs.

Testing: tests/run.sh runs offline against a stub MAME, a stub notify-send and a stub quickshell. It covers lint, marketplace layout rules, every CLI path, install/uninstall, the update helper against file:// fixtures, and 35 Brick Blitz rules run headless. CI runs it on every push.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
