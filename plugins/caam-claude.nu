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
# Returns list of profile IDs like ["claude/dev", "claude/org", ...]
def get-profiles [] {
    # Check if caam is available
    if (which caam | is-empty) {
        print $"(ansi red)Error: caam not found in PATH(ansi reset)"
        return []
    }
    
    # Get profiles from caam
    # Output format: "  claude/dev  dev@cavort-it.systems - Dev account"
    let result = (do { caam profile list claude } | complete)
    if $result.exit_code != 0 {
        return []
    }
    
    # Extract just the profile ID (first token after trimming)
    # Line format: "  claude/dev  dev@cavort-it.systems - Dev account"
    $result.stdout 
        | lines 
        | where { $in | str trim | is-not-empty }
        | each {|line| $line | str trim | split row " " | first }
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
            display: $"  (ansi yellow)∞ Endless mode(ansi reset) (ansi dark_gray)- rotate profiles on exit/limit(ansi reset)"
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
# For endless mode, profiles should be a list to rotate through
def build-command [profile: string, config: record, endless: bool, all_profiles: list<string> = []] {
    let args = ($config | get -o claude_args | default "--dangerously-skip-permissions")
    
    if $endless {
        # Endless mode: rotate through all profiles when one exits (e.g., rate limit)
        let profiles_quoted = ($all_profiles | each {|p| $"\"($p)\""} | str join " ")
        let n = ($all_profiles | length)
        let pct = "%"  # Escape percent for nushell
        # Use bash array syntax
        $"bash -c 'profiles=\(($profiles_quoted)\); n=($n); i=0; while true; do p=\"\\${profiles[\\$i]}\"; echo -e \"\\n\\033[33m∞ Starting profile \\$\(\(i+1\)\)/\\$n: \\$p\\033[0m\"; caam exec claude \\$p -- ($args); code=\\$?; echo -e \"\\033[90mProfile \\$p exited \(code \\$code\). Rotating to next in 2s...\\033[0m\"; sleep 2; i=\\$\(\( \(i+1\) ($pct) n \)\); done'"
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
    
    if $endless {
        # Endless mode: rotate through ALL profiles
        let command = (build-command "" $config true $profiles)
        return { 
            command: $command
            window_name: $"($name) [∞]"
        }
    }
    
    # Single profile mode
    let command = (build-command $selection $config false)
    
    # Return command for qs to execute
    { 
        command: $command
        window_name: $"($name) [($selection)]"
    }
}
