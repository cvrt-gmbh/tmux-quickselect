#!/usr/bin/env bash
# tmux-quickselect installer

set -euo pipefail

REPO_URL="https://github.com/cvrt-jh/tmux-quickselect.git"
INSTALL_DIR="${HOME}/.config/tmux-quickselect"
NU_CONFIG="${HOME}/.config/nushell/config.nu"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}==>${NC} $1"; exit 1; }

main() {
    info "Installing tmux-quickselect..."

    # Check for Nushell
    if ! command -v nu &> /dev/null; then
        error "Nushell is required but not installed. Visit https://www.nushell.sh/"
    fi

    # Clone or update repository
    if [[ -d "$INSTALL_DIR" ]]; then
        info "Updating existing installation..."
        git -C "$INSTALL_DIR" pull --quiet
    else
        info "Cloning repository..."
        git clone --quiet "$REPO_URL" "$INSTALL_DIR"
    fi

    # Add source to Nushell config
    if [[ -f "$NU_CONFIG" ]]; then
        if ! grep -q "tmux-quickselect/qs.nu" "$NU_CONFIG"; then
            info "Adding to Nushell config..."
            echo "" >> "$NU_CONFIG"
            echo "# tmux-quickselect: Directory selector" >> "$NU_CONFIG"
            echo "source ~/.config/tmux-quickselect/qs.nu" >> "$NU_CONFIG"
        else
            warn "Already in Nushell config, skipping..."
        fi
    else
        warn "Nushell config not found at $NU_CONFIG"
        warn "Add manually: source ~/.config/tmux-quickselect/qs.nu"
    fi

    echo ""
    info "Installation complete!"
    echo ""
    echo "1. Edit config: ~/.config/tmux-quickselect/config.nuon"
    echo ""
    echo "2. Add tmux keybinding (optional):"
    echo "   bind-key O display-popup -E -w 70% -h 60% \"nu --login --interactive -c 'qs --tmux'\""
    echo ""
    echo "Usage:"
    echo "  qs        - Select directory"
    echo "  qs --tmux - Open in new tmux window"
    echo ""
}

main "$@"
