# caam-claude.nu
# Plugin for tmux-quickselect: CAAM multi-profile Claude launcher
# https://github.com/cvrt-gmbh/tmux-quickselect

# Plugin metadata
export const PLUGIN_NAME = "caam-claude"
export const PLUGIN_DESC = "Launch Claude with CAAM profile selection"
export const PLUGIN_VERSION = "1.0.0"

# Plugin configuration schema (merged with user config)
export def default-config [] {
    {
        # Available profiles (auto-detected if empty)
        profiles: []
        # Default profile to use (skips selection if set)
        default_profile: null
        # Claude CLI arguments
        claude_args: "--dangerously-skip-permissions"
        # Show "endless" mode option (restarts on exit)
        show_endless: true
    }
}

# Get available CAAM profiles for Claude
def get-profiles [] {
    # Check if caam is available
    if (which caam | is-empty) {
        print $"(ansi red)Error: caam not found in PATH(ansi reset)"
        return []
    }
    
    # Get profiles from caam
    let result = (do { caam profile list claude } | complete)
    if $result.exit_code != 0 {
        return []
    }
    
    # Parse profile list (one per line)
    $result.stdout | lines | where { $in | str trim | is-not-empty }
}

# Show profile selection UI
def select-profile [profiles: list<string>, config: record] {
    let show_endless = ($config | get -o show_endless | default true)
    
    # Build menu items
    mut items = ($profiles | each {|p| 
        { display: $"  ($p)", value: $p, type: "profile" }
    })
    
    if $show_endless {
        $items = ($items | append { 
            display: $"  (ansi yellow)∞ Endless mode(ansi reset) (ansi dark_gray)- auto-restart on exit(ansi reset)"
            value: "endless"
            type: "special"
        })
    }
    
    # Add cancel option
    $items = ($items | append {
        display: $"  (ansi dark_gray)✕ Cancel(ansi reset)"
        value: "cancel"
        type: "special"
    })
    
    let displays = ($items | get display)
    
    print ""
    print $"(ansi cyan)━━━ Select Claude Profile ━━━(ansi reset)"
    print ""
    
    let selected = ($displays | input list --fuzzy $"Profile: ")
    
    if ($selected | is-empty) {
        return null
    }
    
    let item = ($items | where display == $selected | first)
    $item.value
}

# Build the command to execute
def build-command [profile: string, config: record, endless: bool] {
    let args = ($config | get -o claude_args | default "--dangerously-skip-permissions")
    
    if $endless {
        # Endless mode: loop until user explicitly exits
        $"while true; do caam exec claude ($profile) -- ($args); echo 'Press Ctrl+C to exit, or wait to restart...'; sleep 2; done"
    } else {
        $"caam exec claude ($profile) -- ($args)"
    }
}

# Main plugin entry point
# Called by qs after directory selection
# Returns: { command: string } or null to cancel
export def run [
    path: string,           # Selected directory path
    name: string,           # Directory name (for window title)
    plugin_config: record,  # Plugin-specific config from user's config.nuon
    tmux: bool              # Whether running in tmux mode
] {
    # Merge with defaults
    let config = (default-config | merge $plugin_config)
    
    # Get profiles
    let profiles = if ($config.profiles | is-empty) {
        get-profiles
    } else {
        $config.profiles
    }
    
    if ($profiles | is-empty) {
        print $"(ansi red)No CAAM profiles found for Claude(ansi reset)"
        print $"(ansi dark_gray)Run: caam profile add claude <profile-name>(ansi reset)"
        return null
    }
    
    # Check for default profile
    let default = ($config | get -o default_profile)
    let selection = if ($default != null) and ($default in $profiles) {
        $default
    } else if ($profiles | length) == 1 {
        # Only one profile, use it directly
        $profiles | first
    } else {
        # Show selection UI
        select-profile $profiles $config
    }
    
    if ($selection == null) or ($selection == "cancel") {
        return null
    }
    
    let endless = ($selection == "endless")
    let profile = if $endless {
        # For endless mode, need to pick a profile first
        let filtered = ($profiles | where { $in != "endless" })
        if ($filtered | length) == 1 {
            $filtered | first
        } else {
            print ""
            print $"(ansi yellow)Select profile for endless mode:(ansi reset)"
            let p = ($filtered | input list --fuzzy "Profile: ")
            if ($p | is-empty) { return null }
            $p
        }
    } else {
        $selection
    }
    
    let command = (build-command $profile $config $endless)
    
    # Return command for qs to execute
    { 
        command: $command
        window_name: $"($name) [($profile)]"
    }
}
