# tmux-quickselect

A fast, interactive directory selector for tmux.

> **Note:** Currently only tested with [Nushell](https://www.nushell.sh/). Bash/Zsh support planned.

## Features

- **Fuzzy search** - Find directories instantly
- **Usage tracking** - Sorted by "last used" with relative timestamps
- **Configurable** - Define your own watch directories
- **tmux integration** - Launch in popup, open in new window
- **Homebrew-style UI** - Clean, colored interface
- **Optional command** - Run any command after selection (or just cd)
- **In-app settings** - Configure sort order and command from the menu

## Requirements

- [Nushell](https://www.nushell.sh/) v0.90+
- [tmux](https://github.com/tmux/tmux) (optional, for popup/window features)

## Installation

### Homebrew (recommended)

```bash
brew tap cvrt-gmbh/tmux-quickselect
brew install tmux-quickselect

# Complete setup
qs-install
```

### Manual

```bash
# Clone the repository
git clone https://github.com/cvrt-gmbh/tmux-quickselect.git ~/.config/tmux-quickselect

# Add to your Nushell config (~/.config/nushell/config.nu)
source ~/.config/tmux-quickselect/qs.nu
```

### tmux Keybinding (optional)

Add to your `tmux.conf`:

```bash
# Quick select popup (prefix + O)
bind-key O display-popup -E -w 70% -h 60% "nu --login -c 'qs --tmux'"
```

## Configuration

Copy `config.nuon` to `~/.config/tmux-quickselect/config.nuon` and customize:

```nuon
{
    # Directories to scan (subdirectories become selectable)
    directories: [
        { path: "~/Git/work", label: "work", color: "cyan" }
        { path: "~/Git/personal", label: "personal", color: "magenta" }
        { path: "~/projects", label: "proj", color: "green" }
    ]

    # Command to run after selecting (empty = just cd)
    command: "nvim"  # or "opencode", "code .", "" for none

    # Cache directory for usage history
    cache_dir: "~/.cache/tmux-quickselect"

    # UI customization
    ui: {
        title: "Quick Select"
        icon: "📂"
        width: 25
    }
}
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `directories[].path` | Directory to scan | required |
| `directories[].label` | Short label in list | required |
| `directories[].color` | cyan, magenta, green, yellow, blue, red | cyan |
| `command` | Command after selection (empty = none) | `""` |
| `sort` | Sort order: `recent`, `alphabetical`, `label` | `recent` |
| `cache_dir` | History storage location | `~/.cache/tmux-quickselect` |
| `ui.title` | Header title | `Quick Select` |
| `ui.icon` | Header icon | `📂` |
| `ui.width` | Column width for names | `25` |

### Interactive Navigation

Directories with subdirectories show a `→` indicator. Select them to drill down:

```
  git  client-a                    →  2h ago
  git  client-b                    →  -
  git  standalone-project             1d ago
```

When browsing inside a directory:
- **`← ..`** - Go back to parent directory
- **`✓ Select this folder`** - Select the current directory
- Select a subdirectory to drill deeper

This is useful when you organize projects in nested folders like `~/Git/client/project/`.

## Usage

```bash
qs          # Select directory and cd into it
qs --tmux   # Open in new tmux window
qs -t       # Short form
```

### tmux Popup

Press `prefix + O` (e.g., `Ctrl+A` then `Shift+O`) to open the selector in a popup.

## Example

```
══════════════════════════════════════════════════════════
  📂 Quick Select
══════════════════════════════════════════════════════════

  work: 6    personal: 11

Select: |
> work  my-app                    just now
  work  api-server                2h ago
  personal  dotfiles              1d ago
  personal  blog                  3d ago
  work  legacy-code               -
```

## Limitations

- **Timestamp tracking**: The "last used" timestamp is only updated when selecting via `qs`. Regular `cd` commands are not tracked. For full directory tracking, consider integrating with [zoxide](https://github.com/ajeetdsouza/zoxide).

## License

MIT
