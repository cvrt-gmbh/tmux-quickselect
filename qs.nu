# qs.nu
# tmux-quickselect: Interactive directory launcher for tmux with Nushell
# https://github.com/cvrt-gmbh/tmux-quickselect

# ============ Configuration ============

const CONFIG_FILE = "~/.config/tmux-quickselect/config.nuon"
const PLUGIN_DIR = "/opt/homebrew/opt/tmux-quickselect/libexec/plugins"
const USER_PLUGIN_DIR = "~/.config/tmux-quickselect/plugins"

def get-config [] {
    let config_file = ($CONFIG_FILE | path expand)
    
    if not ($config_file | path exists) {
        # Default configuration
        {
            directories: [
                { path: "~/Git", label: "git", color: "cyan" }
            ]
            command: ""
            sort: "recent"
            cache_dir: "~/.cache/tmux-quickselect"
            ui: { title: "Quick Select", icon: "📂", width: 25 }
        }
    } else {
        open $config_file
    }
}

def save-config [config: record] {
    let config_file = ($CONFIG_FILE | path expand)
    mkdir ($config_file | path dirname)
    $config | to nuon | save -f $config_file
}

# ============ Helper Functions ============

def format-ago [timestamp: string] {
    let diff = (date now) - ($timestamp | into datetime)
    if $diff < 1min {
        "just now"
    } else if $diff < 1hr {
        $"($diff / 1min | math floor)m ago"
    } else if $diff < 24hr {
        $"($diff / 1hr | math floor)h ago"
    } else if $diff < 7day {
        $"($diff / 1day | math floor)d ago"
    } else {
        $"($diff / 1wk | math floor)w ago"
    }
}

def get-ansi-color [color: string] {
    match $color {
        "cyan" => (ansi cyan)
        "magenta" => (ansi magenta)
        "green" => (ansi green)
        "yellow" => (ansi yellow)
        "blue" => (ansi blue)
        "red" => (ansi red)
        "white" => (ansi white)
        _ => (ansi cyan)
    }
}

# Check if directory has subdirectories
def has-subdirs [path: string, show_hidden: bool] {
    let expanded = ($path | path expand)
    if not ($expanded | path exists) {
        return false
    }
    
    let entries = if $show_hidden {
        ls -a $expanded | where type == dir | where name !~ '/\\.\\.$' | where name !~ '/\\.$'
    } else {
        ls $expanded | where type == dir
    }
    
    ($entries | length) > 0
}

# Get subdirectories of a path
def get-subdirs [path: string, show_hidden: bool] {
    let expanded = ($path | path expand)
    if not ($expanded | path exists) {
        return []
    }
    
    if $show_hidden {
        ls -a $expanded | where type == dir | where name !~ '/\\.\\.$' | where name !~ '/\\.$' | each {|it| $it.name | path expand }
    } else {
        ls $expanded | where type == dir | each {|it| $it.name | path expand }
    }
}

# ============ Plugin System ============

# Find plugin file path
def find-plugin [name: string] {
    # Check user plugins first
    let user_path = ($"($USER_PLUGIN_DIR)/($name).nu" | path expand)
    if ($user_path | path exists) {
        return $user_path
    }
    
    # Check system plugins
    let system_path = $"($PLUGIN_DIR)/($name).nu"
    if ($system_path | path exists) {
        return $system_path
    }
    
    null
}

# Execute plugin and get command to run
def run-plugin [
    plugin_name: string,
    path: string,
    name: string,
    plugin_config: record,
    tmux: bool
] {
    let plugin_path = (find-plugin $plugin_name)
    
    if ($plugin_path == null) {
        print $"(ansi red)Plugin not found: ($plugin_name)(ansi reset)"
        print $"(ansi dark_gray)Searched: ($USER_PLUGIN_DIR | path expand), ($PLUGIN_DIR)(ansi reset)"
        return null
    }
    
    # Write plugin config to temp file for the subprocess to read
    let temp_config = (mktemp -t qs-plugin-config.XXXXXX)
    let temp_result = (mktemp -t qs-plugin-result.XXXXXX)
    $plugin_config | to nuon | save -f $temp_config
    
    # Run plugin interactively (no pipe capture) - it writes result to temp file
    # This allows input list and other interactive commands to work
    nu --login -c $"
        source '($plugin_path)'
        let cfg = \(open '($temp_config)' | from nuon\)
        let result = \(run '($path)' '($name)' $cfg ($tmux)\)
        if \($result != null\) {
            $result | to nuon | save -f '($temp_result)'
        }
    "
    
    # Read result from temp file
    let result = if ($temp_result | path exists) and (open $temp_result | str trim | is-not-empty) {
        try {
            open $temp_result | from nuon
        } catch {
            null
        }
    } else {
        null
    }
    
    # Cleanup temp files
    rm -f $temp_config $temp_result
    
    $result
}

# Execute the final command (either from plugin or config.command)
# Returns: true if executed, false if cancelled (should go back)
def execute-selection [
    config: record,
    selection_path: string,
    selection_name: string,
    tmux: bool,
    line: string
]: nothing -> bool {
    let debug_log = "/tmp/qs-debug.log"
    $"[(date now | format date '%Y-%m-%d %H:%M:%S')] execute-selection called\n" | save -a $debug_log
    $"  selection_path: ($selection_path)\n" | save -a $debug_log
    $"  selection_name: ($selection_name)\n" | save -a $debug_log
    $"  tmux: ($tmux)\n" | save -a $debug_log
    
    let plugin_name = ($config | get -o plugin | default null)
    let plugin_config = ($config | get -o plugin_config | default {})
    $"  plugin_name: ($plugin_name)\n" | save -a $debug_log
    
    # Determine command and window name
    let result = if ($plugin_name != null) {
        # Use plugin
        $"  -> calling run-plugin\n" | save -a $debug_log
        run-plugin $plugin_name $selection_path $selection_name $plugin_config $tmux
    } else {
        # Use simple command from config
        let cmd = ($config | get -o command | default "")
        { command: $cmd, window_name: $selection_name }
    }
    
    $"  plugin result: ($result | to nuon)\n" | save -a $debug_log
    
    # If plugin returned null, it cancelled - signal to go back
    if ($result == null) {
        $"  -> plugin returned null, going back\n" | save -a $debug_log
        return false
    }
    
    let command = ($result | get -o command | default "")
    let window_name = ($result | get -o window_name | default $selection_name)
    
    # Debug log to file (always, for troubleshooting)
    let debug_log = "/tmp/qs-debug.log"
    $"[(date now | format date '%Y-%m-%d %H:%M:%S')] qs execute\n" | save -a $debug_log
    $"  tmux mode: ($tmux)\n" | save -a $debug_log
    $"  window_name: ($window_name)\n" | save -a $debug_log
    $"  selection_path: ($selection_path)\n" | save -a $debug_log
    $"  command length: ($command | str length)\n" | save -a $debug_log
    $"  command starts with 'bash -c': ($command | str starts-with 'bash -c')\n" | save -a $debug_log
    $"  command: ($command)\n" | save -a $debug_log
    
    if $tmux {
        # Open in new tmux window
        if ($command | is-empty) {
            $"  -> executing: tmux new-window -n <name> -c <path> (no command)\n" | save -a $debug_log
            tmux new-window -n $window_name -c $selection_path
        } else if ($command | str starts-with "bash -c") {
            # Command is already a bash script, run directly
            $"  -> executing: tmux new-window -n <name> -c <path> <bash command>\n" | save -a $debug_log
            let result = (do { tmux new-window -n $window_name -c $selection_path $command } | complete)
            $"  -> exit code: ($result.exit_code)\n" | save -a $debug_log
            if $result.exit_code != 0 {
                $"  -> stderr: ($result.stderr)\n" | save -a $debug_log
            }
        } else {
            # Wrap in nu --login for nushell commands
            let full_cmd = $"nu --login -c '($command)'"
            $"  -> executing: tmux new-window -n <name> -c <path> <nu wrapped>\n" | save -a $debug_log
            tmux new-window -n $window_name -c $selection_path $full_cmd
        }
    } else {
        print ""
        print $"(ansi green)($line)(ansi reset)"
        print $"(ansi green)  ✓(ansi reset) Selected (ansi white_bold)($selection_name)(ansi reset)"
        print $"(ansi dark_gray)  → ($selection_path)(ansi reset)"
        print $"(ansi green)($line)(ansi reset)"
        cd $selection_path
        
        # Run the command if set
        if ($command | is-not-empty) {
            nu -c $command
        }
    }
    
    true
}

# ============ Main Command ============

# Interactive directory selector for tmux
# Usage: qs           - select and cd into directory
#        qs --tmux    - open in new tmux window (for popup use)
#        qs --path    - start browsing from a specific path
#        qs --debug   - show debug info and wait
export def --env qs [--tmux (-t), --debug (-d), --path (-p): string] {
    if $debug {
        print $"(ansi yellow)DEBUG: qs started(ansi reset)"
        print $"  PWD: ($env.PWD)"
        print $"  TERM: ($env.TERM? | default 'not set')"
        print $"  TMUX: ($env.TMUX? | default 'not set')"
        print ""
    }
    let config = (get-config)
    let cache_file = ($"($config.cache_dir)/history.nuon" | path expand)
    
    # Ensure cache directory exists
    mkdir ($cache_file | path dirname)
    
    # Load history or create empty record
    let history = if ($cache_file | path exists) {
        open $cache_file
    } else {
        {}
    }

    # Scan directories - either from --path or from configured directories
    let show_hidden = ($config | get -o show_hidden | default false)
    let browsing_path = $path  # The --path parameter
    
    let all_projects = if ($browsing_path | is-not-empty) {
        # Browsing inside a specific directory
        let expanded = ($browsing_path | path expand)
        let subdirs = (get-subdirs $expanded $show_hidden)
        
        # Find which configured directory this belongs to (for label/color)
        let parent_config = ($config.directories | where {|dir| 
            $expanded | str starts-with ($dir.path | path expand)
        } | first | default { label: "browse", color: "white" })
        
        $subdirs | each {|p| 
            { 
                name: ($p | path basename)
                path: $p
                label: $parent_config.label
                color: $parent_config.color
            }
        }
    } else {
        # Normal mode: scan configured directories at depth 1
        $config.directories | each {|dir|
            let expanded_path = ($dir.path | path expand)
            let found_paths = (get-subdirs $expanded_path $show_hidden)
            $found_paths | each {|p| 
                { 
                    name: ($p | path basename)
                    path: $p
                    label: $dir.label
                    color: $dir.color
                }
            }
        } | flatten
    }

    # Add last_used timestamp
    let projects_with_history = ($all_projects | each {|proj|
        let last_used = ($history | get -o $proj.path | default null)
        $proj | insert last_used $last_used
    })

    # Sort based on config (default: recent)
    # Can be a string ("recent", "alphabetical", "label") or a list ["label", "recent"]
    let sort_config = ($config | get -o sort | default "recent")
    let sort_keys = if ($sort_config | describe | str starts-with "list") {
        $sort_config
    } else {
        [$sort_config]
    }
    
    # Apply sorting - process keys in reverse order for correct precedence
    let projects = ($sort_keys | reverse | reduce --fold $projects_with_history {|key, acc|
        match $key {
            "recent" => {
                # Recent first: items with timestamp sorted by date, then items without
                let with_ts = ($acc | where last_used != null | sort-by last_used --reverse)
                let without_ts = ($acc | where last_used == null)
                $with_ts | append $without_ts
            }
            "alphabetical" | "name" => {
                $acc | sort-by name
            }
            "label" => {
                $acc | sort-by label
            }
            _ => { $acc }
        }
    })

    # Count projects per group
    let group_counts = ($config.directories | each {|dir|
        let count = ($projects | where label == $dir.label | length)
        { label: $dir.label, count: $count, color: $dir.color }
    })

    # Line decoration for success messages
    let line = "══════════════════════════════════════════════════════════"

    # Build prompt with path info (shown in input list, not printed separately)
    let prompt = if ($browsing_path | is-not-empty) {
        let short_path = ($browsing_path | path expand | str replace $env.HOME "~")
        $"(ansi green)($config.ui.icon)(ansi reset) (ansi dark_gray)($short_path)(ansi reset) (ansi yellow)Select:(ansi reset)"
    } else {
        # Show group counts in prompt for main view
        let counts_str = ($group_counts | each {|g|
            $"(get-ansi-color $g.color)($g.label):(ansi reset)($g.count)"
        } | str join " ")
        $"(ansi green)($config.ui.icon)(ansi reset) ($counts_str) (ansi yellow)Select:(ansi reset)"
    }

    # Build display list for projects
    let project_list = ($projects | each {|proj|
        let prefix = $"(get-ansi-color $proj.color)($proj.label)(ansi reset)"
        let time_str = if $proj.last_used != null {
            $"(ansi dark_gray)(format-ago $proj.last_used)(ansi reset)"
        } else {
            $"(ansi dark_gray)-(ansi reset)"
        }
        # Check if this directory has subdirectories (can drill down)
        let has_children = (has-subdirs $proj.path $show_hidden)
        let drill_indicator = if $has_children { $"(ansi cyan)→(ansi reset)" } else { " " }
        let padded_name = ($proj.name | fill -w $config.ui.width)
        { 
            display: $"($prefix)  ($padded_name) ($drill_indicator) ($time_str)"
            path: $proj.path 
            name: $proj.name
            type: "project"
            has_children: $has_children
        }
    })
    
    # Add navigation items when browsing
    let nav_items = if ($browsing_path | is-not-empty) {
        let parent = ($browsing_path | path expand | path dirname)
        let current_name = ($browsing_path | path expand | path basename)
        [
            { display: $"(ansi yellow)←(ansi reset)  (ansi dark_gray)..(ansi reset)  (ansi dark_gray)back to parent(ansi reset)", type: "nav", action: "back", parent: $parent }
            { display: $"(ansi green)✓(ansi reset)  (ansi white_bold)Select this folder(ansi reset)  (ansi dark_gray)($current_name)(ansi reset)", type: "nav", action: "select_current", path: ($browsing_path | path expand), name: $current_name }
            { display: $"(ansi dark_gray)──────────────────────────────────────(ansi reset)", type: "separator", action: "" }
        ]
    } else {
        []
    }

    # Config menu items (only show when not browsing)
    let sort_display = if ($sort_keys | length) == 1 {
        $sort_keys | first
    } else {
        $sort_keys | str join " → "
    }
    let hidden_status = if $show_hidden { "on" } else { "off" }
    let plugin_name = ($config | get -o plugin | default null)
    let action_display = if ($plugin_name != null) {
        $"(ansi magenta)plugin:(ansi reset) ($plugin_name)"
    } else if ($config.command | is-empty) {
        "(none)"
    } else {
        $config.command
    }
    let config_items = if ($browsing_path | is-empty) {
        [
            { display: $"(ansi dark_gray)──────────────────────────────────────(ansi reset)", type: "separator", action: "" }
            { display: $"(ansi yellow)⚙(ansi reset)  Sort: (ansi white_bold)($sort_display)(ansi reset)", type: "config", action: "sort" }
            { display: $"(ansi yellow)⚙(ansi reset)  Action: (ansi white_bold)($action_display)(ansi reset)", type: "config", action: "action" }
            { display: $"(ansi yellow)⚙(ansi reset)  Show hidden: (ansi white_bold)($hidden_status)(ansi reset)", type: "config", action: "toggle_hidden" }
            { display: $"(ansi blue)📄(ansi reset) Edit config", type: "config", action: "edit_config" }
            { display: $"(ansi red)✕(ansi reset)  Clear history", type: "config", action: "clear_history" }
        ]
    } else {
        []
    }

    let display_list = ($nav_items | append $project_list | append $config_items)

    # Show interactive selection menu
    let selection = ($display_list | input list --display display --fuzzy $prompt)

    if ($selection | is-not-empty) {
        match $selection.type {
            "project" => {
                # Check if user wants to drill down (has children) or select
                let has_children = ($selection | get -o has_children | default false)
                
                if $has_children {
                    # Drill down into this directory
                    qs --tmux=$tmux --path $selection.path
                } else {
                    # Select this directory (no children, or leaf node)
                    # Update history
                    let new_history = ($history | upsert $selection.path (date now | format date "%+"))
                    $new_history | save -f $cache_file

                    # Execute using plugin or command
                    let executed = (execute-selection $config $selection.path $selection.name $tmux $line)
                    if not $executed {
                        # Plugin cancelled - go back to selection
                        if $path == null {
                            qs --tmux=$tmux
                        } else {
                            qs --tmux=$tmux --path $path
                        }
                    }
                }
            }
            "nav" => {
                match $selection.action {
                    "back" => {
                        # Go back to parent or root
                        let parent = $selection.parent
                        # Check if parent is one of the configured root directories
                        let is_root = ($config.directories | any {|dir| ($dir.path | path expand) == $parent })
                        if $is_root {
                            # Back to main menu
                            qs --tmux=$tmux
                        } else {
                            # Continue browsing parent
                            qs --tmux=$tmux --path $parent
                        }
                    }
                    "select_current" => {
                        # Select the current browsing directory
                        let new_history = ($history | upsert $selection.path (date now | format date "%+"))
                        $new_history | save -f $cache_file

                        # Execute using plugin or command
                        let executed = (execute-selection $config $selection.path $selection.name $tmux $line)
                        if not $executed {
                            # Plugin cancelled - go back to selection
                            qs --tmux=$tmux --path $selection.path
                        }
                    }
                }
            }
            "config" => {
                match $selection.action {
                    "sort" => {
                        print ""
                        print $"(ansi yellow)Configure sort order:(ansi reset)"
                        print $"(ansi dark_gray)Current: ($sort_display)(ansi reset)"
                        print ""
                        print "  1 = recent (last used first)"
                        print "  2 = alphabetical (A-Z)"
                        print "  3 = label (grouped by label)"
                        print ""
                        print $"(ansi dark_gray)Enter numbers in order, e.g. '31' = label then recent(ansi reset)"
                        let input = (input "Sort order: ")
                        
                        if ($input | is-not-empty) {
                            let sort_map = { "1": "recent", "2": "alphabetical", "3": "label" }
                            let new_sort = ($input | split chars | each {|c| $sort_map | get -o $c } | where { $in != null })
                            
                            if ($new_sort | is-not-empty) {
                                let sort_value = if ($new_sort | length) == 1 { $new_sort | first } else { $new_sort }
                                let new_config = ($config | upsert sort $sort_value)
                                save-config $new_config
                            }
                        }
                    }
                    "action" => {
                        # Configure what happens after directory selection
                        print ""
                        print $"(ansi yellow)Configure action after selection:(ansi reset)"
                        print $"(ansi dark_gray)Current: ($action_display)(ansi reset)"
                        print ""
                        
                        # Find available plugins
                        let user_plugins_dir = ($USER_PLUGIN_DIR | path expand)
                        let user_plugins = if ($user_plugins_dir | path exists) {
                            ls $user_plugins_dir | where name =~ '\.nu$' | each {|f| $f.name | path basename | str replace '.nu' '' }
                        } else { [] }
                        
                        let system_plugins = if ($PLUGIN_DIR | path exists) {
                            ls $PLUGIN_DIR | where name =~ '\.nu$' | each {|f| $f.name | path basename | str replace '.nu' '' }
                        } else { [] }
                        
                        let all_plugins = ($user_plugins | append $system_plugins | uniq | where { $in != "default" })
                        
                        # Build menu
                        mut menu_items = [
                            { display: $"(ansi green)▸(ansi reset) Simple command", value: "__COMMAND__", type: "command" }
                            { display: $"(ansi red)✕(ansi reset) None (just open shell)", value: "__NONE__", type: "none" }
                        ]
                        
                        if ($all_plugins | is-not-empty) {
                            $menu_items = ($menu_items | append { display: $"(ansi dark_gray)── Plugins ──(ansi reset)", value: "__SEP__", type: "separator" })
                            $menu_items = ($menu_items | append ($all_plugins | each {|p|
                                { display: $"(ansi magenta)◆(ansi reset) ($p)", value: $p, type: "plugin" }
                            }))
                        }
                        
                        let selection = ($menu_items | input list --display display "Action:")
                        
                        if ($selection | is-not-empty) and ($selection.type != "separator") {
                            if $selection.type == "command" {
                                # Show command input
                                let cmd_history_file = ($"($config.cache_dir)/command_history.nuon" | path expand)
                                let cmd_history = if ($cmd_history_file | path exists) {
                                    open $cmd_history_file | default []
                                } else { [] }
                                
                                let new_cmd = if ($cmd_history | is-empty) {
                                    input "Command: "
                                } else {
                                    let history_items = ($cmd_history | each {|cmd|
                                        { display: $"  ($cmd)", value: $cmd }
                                    })
                                    let cmd_menu = [{ display: $"(ansi yellow)▸(ansi reset) Type new...", value: "__NEW__" }] | append $history_items
                                    let sel = ($cmd_menu | input list --display display "Command:")
                                    if ($sel | is-empty) { null }
                                    else if $sel.value == "__NEW__" { input "Command: " }
                                    else { $sel.value }
                                }
                                
                                if ($new_cmd != null) {
                                    let new_config = ($config | reject -o plugin | reject -o plugin_config | upsert command $new_cmd)
                                    save-config $new_config
                                    
                                    if ($new_cmd | is-not-empty) and ($new_cmd not-in $cmd_history) {
                                        let updated_history = ([$new_cmd] | append $cmd_history | take 10)
                                        $updated_history | save -f $cmd_history_file
                                    }
                                }
                            } else if $selection.type == "none" {
                                let new_config = ($config | reject -o plugin | reject -o plugin_config | upsert command "")
                                save-config $new_config
                            } else if $selection.type == "plugin" {
                                let new_config = ($config | upsert plugin $selection.value | upsert command "" | upsert plugin_config {})
                                save-config $new_config
                                print $"(ansi green)Plugin '($selection.value)' activated(ansi reset)"
                                print $"(ansi dark_gray)Edit config.nuon to customize plugin_config(ansi reset)"
                            }
                        }
                    }
                    "toggle_hidden" => {
                        let new_value = not $show_hidden
                        let new_config = ($config | upsert show_hidden $new_value)
                        save-config $new_config
                    }
                    "edit_config" => {
                        let config_path = ($CONFIG_FILE | path expand)
                        let editor = ($env | get -o EDITOR | default "nano")
                        ^$editor $config_path
                    }
                    "clear_history" => {
                        {} | save -f $cache_file
                    }
                }
                # Re-run qs to stay in menu after config changes
                qs --tmux=$tmux
            }
            "separator" => {
                # Do nothing for separator
            }
        }
    }
}
