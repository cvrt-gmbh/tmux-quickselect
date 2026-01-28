# typed: false
# frozen_string_literal: true

class TmuxQuickselect < Formula
  desc "Fast, interactive directory selector for tmux with Nushell"
  homepage "https://github.com/cvrt-gmbh/tmux-quickselect"
  url "https://github.com/cvrt-gmbh/tmux-quickselect.git",
      tag:      "v1.0.3",
      revision: "02b1eb293fecf91e58170e3b2f30b98bee5f1259"
  license "MIT"
  head "https://github.com/cvrt-gmbh/tmux-quickselect.git", branch: "main"

  depends_on "nushell"

  def install
    libexec.install "qs.nu"
    (libexec/"plugins").install Dir["plugins/*.nu"]
    (share/"tmux-quickselect").install "config.nuon"

    (bin/"qs-install").write <<~EOS
      #!/bin/bash
      # tmux-quickselect post-install setup
      
      set -euo pipefail
      
      # Colors
      GREEN='\\033[0;32m'
      YELLOW='\\033[0;33m'
      CYAN='\\033[0;36m'
      NC='\\033[0m'
      
      CONFIG_DIR="$HOME/.config/tmux-quickselect"
      QS_SOURCE="#{opt_libexec}/qs.nu"
      TMUX_BIND='bind-key O display-popup -E -w 70% -h 60% "nu --login -c '"'"'qs --tmux'"'"'"'
      
      # Detect Nushell config location
      if [[ -f "$HOME/Library/Application Support/nushell/config.nu" ]]; then
        NU_CONFIG="$HOME/Library/Application Support/nushell/config.nu"
      elif [[ -f "$HOME/.config/nushell/config.nu" ]]; then
        NU_CONFIG="$HOME/.config/nushell/config.nu"
      else
        NU_CONFIG=""
      fi
      
      # Detect tmux config location
      if [[ -f "$HOME/.config/tmux/tmux.conf" ]]; then
        TMUX_CONFIG="$HOME/.config/tmux/tmux.conf"
      elif [[ -f "$HOME/.tmux.conf" ]]; then
        TMUX_CONFIG="$HOME/.tmux.conf"
      else
        TMUX_CONFIG=""
      fi
      
      echo -e "${GREEN}tmux-quickselect setup${NC}"
      echo ""
      
      # Step 1: Create config directory
      mkdir -p "$CONFIG_DIR"
      if [[ ! -f "$CONFIG_DIR/config.nuon" ]]; then
        cp "#{share}/tmux-quickselect/config.nuon" "$CONFIG_DIR/"
        echo -e "✓ Config created at ${CYAN}$CONFIG_DIR/config.nuon${NC}"
      else
        echo -e "• Config exists at ${CYAN}$CONFIG_DIR/config.nuon${NC}"
      fi
      echo ""
      
      # Step 2: Setup choice
      echo "How would you like to configure tmux-quickselect?"
      echo ""
      echo "  1) Auto-configure (edit configs automatically)"
      echo "  2) Manual setup (show copy-paste instructions)"
      echo ""
      read -p "Choose [1/2]: " choice
      echo ""
      
      case "$choice" in
        1)
          # Auto-configure Nushell
          if [[ -n "$NU_CONFIG" ]]; then
            if ! grep -q "qs.nu" "$NU_CONFIG" 2>/dev/null; then
              echo "" >> "$NU_CONFIG"
              echo "# tmux-quickselect: Directory selector" >> "$NU_CONFIG"
              echo "# https://github.com/cvrt-gmbh/tmux-quickselect" >> "$NU_CONFIG"
              echo "source $QS_SOURCE" >> "$NU_CONFIG"
              echo -e "✓ Added to Nushell config: ${CYAN}$NU_CONFIG${NC}"
            else
              echo -e "• Already in Nushell config"
            fi
          else
            echo -e "${YELLOW}⚠ Nushell config not found. Add manually:${NC}"
            echo -e "  source $QS_SOURCE"
          fi
          
          # Auto-configure tmux
          if [[ -n "$TMUX_CONFIG" ]]; then
            if ! grep -q "qs --tmux" "$TMUX_CONFIG" 2>/dev/null; then
              echo "" >> "$TMUX_CONFIG"
              echo "# tmux-quickselect: Quick directory selector (Ctrl+A O)" >> "$TMUX_CONFIG"
              echo "# https://github.com/cvrt-gmbh/tmux-quickselect" >> "$TMUX_CONFIG"
              echo "$TMUX_BIND" >> "$TMUX_CONFIG"
              echo -e "✓ Added to tmux config: ${CYAN}$TMUX_CONFIG${NC}"
            else
              echo -e "• Already in tmux config"
            fi
          else
            echo -e "${YELLOW}⚠ tmux config not found. Add manually:${NC}"
            echo -e "  $TMUX_BIND"
          fi
          
          echo ""
          echo -e "${GREEN}Setup complete!${NC}"
          echo ""
          read -p "Press Enter to reload shell..." _
          exec nu --login
          ;;
        
        2|*)
          # Manual instructions
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
          echo -e "${GREEN}After adding, restart your shell and tmux.${NC}"
          ;;
      esac
    EOS
  end

  def caveats
    <<~EOS
      Run 'qs-install' to complete setup, or manually:

      1. Add to Nushell config:
         source #{libexec}/qs.nu

      2. Add tmux keybinding:
         bind-key O display-popup -E -w 70% -h 60% "nu --login -c 'qs --tmux'"
    EOS
  end

  test do
    assert_predicate libexec/"qs.nu", :exist?
  end
end
