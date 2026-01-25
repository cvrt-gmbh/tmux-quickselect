#!/usr/bin/env bash
# tmux-quickselect installer (non-Homebrew)
# For Homebrew: brew install cvrt-gmbh/tmux-quickselect/tmux-quickselect

set -euo pipefail

REPO_URL="https://github.com/cvrt-gmbh/tmux-quickselect.git"
INSTALL_DIR="${HOME}/.config/tmux-quickselect"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}==>${NC} $1"; exit 1; }

# Detect Nushell config location
detect_nu_config() {
    if [[ -f "$HOME/Library/Application Support/nushell/config.nu" ]]; then
        echo "$HOME/Library/Application Support/nushell/config.nu"
    elif [[ -f "$HOME/.config/nushell/config.nu" ]]; then
        echo "$HOME/.config/nushell/config.nu"
    else
        echo ""
    fi
}

# Detect tmux config location
detect_tmux_config() {
    if [[ -f "$HOME/.config/tmux/tmux.conf" ]]; then
        echo "$HOME/.config/tmux/tmux.conf"
    elif [[ -f "$HOME/.tmux.conf" ]]; then
        echo "$HOME/.tmux.conf"
    else
        echo ""
    fi
}

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

    echo ""
    echo "How would you like to configure tmux-quickselect?"
    echo ""
    echo "  1) Auto-configure (edit configs automatically)"
    echo "  2) Manual setup (show copy-paste instructions)"
    echo ""
    read -p "Choose [1/2]: " choice
    echo ""

    NU_CONFIG=$(detect_nu_config)
    TMUX_CONFIG=$(detect_tmux_config)
    QS_SOURCE="$INSTALL_DIR/qs.nu"
    TMUX_BIND='bind-key O display-popup -E -w 70% -h 60% "nu --login -c '"'"'qs --tmux'"'"'"'

    case "$choice" in
        1)
            # Auto-configure Nushell
            if [[ -n "$NU_CONFIG" ]]; then
                if ! grep -q "qs.nu" "$NU_CONFIG" 2>/dev/null; then
                    echo "" >> "$NU_CONFIG"
                    echo "# tmux-quickselect: Directory selector" >> "$NU_CONFIG"
                    echo "# https://github.com/cvrt-gmbh/tmux-quickselect" >> "$NU_CONFIG"
                    echo "source $QS_SOURCE" >> "$NU_CONFIG"
                    info "Added to Nushell config: $NU_CONFIG"
                else
                    warn "Already in Nushell config"
                fi
            else
                warn "Nushell config not found. Add manually:"
                echo "  source $QS_SOURCE"
            fi

            # Auto-configure tmux
            if [[ -n "$TMUX_CONFIG" ]]; then
                if ! grep -q "qs --tmux" "$TMUX_CONFIG" 2>/dev/null; then
                    echo "" >> "$TMUX_CONFIG"
                    echo "# tmux-quickselect: Quick directory selector (Ctrl+A O)" >> "$TMUX_CONFIG"
                    echo "# https://github.com/cvrt-gmbh/tmux-quickselect" >> "$TMUX_CONFIG"
                    echo "$TMUX_BIND" >> "$TMUX_CONFIG"
                    info "Added to tmux config: $TMUX_CONFIG"
                else
                    warn "Already in tmux config"
                fi
            else
                warn "tmux config not found. Add manually:"
                echo "  $TMUX_BIND"
            fi

            echo ""
            info "Setup complete! Restart your shell and press Ctrl+A O in tmux."
            ;;

        2|*)
            echo -e "${CYAN}━━━ Nushell config ━━━${NC}"
            echo "Add to your config.nu:"
            echo ""
            echo "  # tmux-quickselect"
            echo "  source $QS_SOURCE"
            echo ""
            echo -e "${CYAN}━━━ tmux config ━━━${NC}"
            echo "Add to your tmux.conf:"
            echo ""
            echo "  # tmux-quickselect (Ctrl+A O)"
            echo "  $TMUX_BIND"
            echo ""
            info "After adding, restart your shell and tmux."
            ;;
    esac

    echo ""
    echo "Edit config: $INSTALL_DIR/config.nuon"
    echo ""
    echo "Usage:"
    echo "  qs        - Select directory"
    echo "  qs --tmux - Open in new tmux window"
}

main "$@"
