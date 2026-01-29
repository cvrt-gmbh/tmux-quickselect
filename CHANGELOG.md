# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.4] - 2026-01-29

### Fixed
- Config field access crash when `command` field is missing from user config
- Safely access optional config fields using `get -o` with defaults

### Removed
- Plugin system (reverted due to stability issues)
- `caam-claude` plugin

## [1.0.3] - 2026-01-28

### Added
- **Plugin system** for extensible post-selection actions (removed in 1.0.4)
- `caam-claude` plugin (removed in 1.0.4)

### Fixed
- Interactive commands (claude, caam) now work properly in tmux windows
- Changed `nu -e` to `nu --login -c` for command execution to support interactive CLIs

## [1.0.2] - 2026-01-25

### Added
- "Press Enter to reload shell" prompt after auto-configure completes
- Automatically reloads nushell after setup

## [1.0.1] - 2026-01-25

### Changed
- `qs-install` now offers interactive setup dialog:
  - Option 1: Auto-configure (edits nushell and tmux configs automatically)
  - Option 2: Manual setup (prints copy-paste instructions)
- Auto-detects nushell config location (macOS `~/Library/...` or XDG `~/.config/...`)
- Auto-detects tmux config location (`~/.config/tmux/` or `~/.tmux.conf`)
- Uses stable Homebrew path (`/opt/homebrew/opt/...`) instead of versioned Cellar path

### Fixed
- Repository URL updated from cvrt-jh to cvrt-gmbh

## [1.0.0] - 2026-01-24

### Changed
- Moved repository from cvrt-jh to cvrt-gmbh
- First stable release

## [0.3.0] - 2026-01-23

### Added
- Interactive drill-down navigation for nested folder structures
- `→` indicator on directories with subdirectories
- `← ..` navigation to go back to parent directory
- `✓ Select this folder` option to select current browsing directory
- `--path` parameter for starting from a specific directory
- Header shows current path when browsing

### Changed
- Removed static `depth` config option in favor of interactive navigation
- Config menu only shows in main view (not when browsing)

## [0.2.3] - 2026-01-10

### Added
- Command history for quick selection
- Arrow key navigation to select from previously used commands
- History limited to 10 most recent unique commands

## [0.2.2] - 2026-01-04

### Added
- `show_hidden` config option to include dotfiles/hidden folders
- Toggle hidden files directly from settings menu
- "Edit config" menu item to open config file in $EDITOR

## [0.2.1] - 2026-01-02

### Added
- Custom multi-key sorting (e.g. `["label", "recent"]` for label-grouped then recent)
- Interactive sort config: enter `31` for label → recent
- Sort display shows chain with arrows (e.g. `label → recent`)

## [0.2.0] - 2026-01-02

### Added
- Homebrew formula for easy installation (`brew tap cvrt-jh/tmux-quickselect`)
- Interactive config menu at bottom of selection list
  - Sort order selection (recent/alphabetical/label)
  - Command configuration
  - Clear history option
- Configurable sort order via `sort` config option
- `qs-install` helper script for post-brew setup

### Fixed
- Nushell 0.109 compatibility for `else if` syntax
- Recently used items now correctly appear at top of list
- Config loading from `~/.config/tmux-quickselect/config.nuon`

## [0.1.0] - 2026-01-02

### Added
- Initial release
- Interactive directory selection with fuzzy search
- Homebrew-style UI with colored headers
- Usage history with relative timestamps ("2h ago", "3d ago")
- Configurable watch directories with labels and colors
- tmux integration with `--tmux` flag
- tmux popup keybinding support (`prefix + O`)
- Optional command execution after selection
- NUON configuration format
