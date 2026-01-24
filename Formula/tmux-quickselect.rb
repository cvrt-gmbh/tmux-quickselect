# typed: false
# frozen_string_literal: true

class TmuxQuickselect < Formula
  desc "Fast, interactive directory selector for tmux with Nushell"
  homepage "https://github.com/cvrt-gmbh/tmux-quickselect"
  url "https://github.com/cvrt-gmbh/tmux-quickselect.git",
      tag:      "v1.0.0",
      revision: "7764c8211b3b6271d7f276be1614ecb0552bc469"
  license "MIT"
  head "https://github.com/cvrt-gmbh/tmux-quickselect.git", branch: "main"

  depends_on "nushell"

  def install
    libexec.install "qs.nu"
    (share/"tmux-quickselect").install "config.nuon"

    (bin/"qs-install").write <<~EOS
      #!/bin/bash
      CONFIG_DIR="$HOME/.config/tmux-quickselect"
      
      echo "Installing tmux-quickselect..."
      mkdir -p "$CONFIG_DIR"
      
      if [ ! -f "$CONFIG_DIR/config.nuon" ]; then
        cp "#{share}/tmux-quickselect/config.nuon" "$CONFIG_DIR/"
        echo "✓ Config created at $CONFIG_DIR/config.nuon"
      else
        echo "• Config exists at $CONFIG_DIR/config.nuon"
      fi
      
      echo ""
      echo "Add to your Nushell config (~/.config/nushell/config.nu):"
      echo "  source #{libexec}/qs.nu"
      echo ""
      echo "Add to tmux config (~/.config/tmux/tmux.conf):"
      echo '  bind-key O display-popup -E -w 70% -h 60% "nu --login -c '"'"'qs --tmux'"'"'"'
      echo ""
      echo "Then restart your shell and try: qs"
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
