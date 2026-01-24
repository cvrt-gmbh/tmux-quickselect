# qs.nu
# tmux-quickselect: Interactive directory launcher for tmux with Nushell
# https://github.com/cvrt-jh/tmux-quickselect

# ============ Configuration ============

const CONFIG_FILE = "~/.config/tmux-quickselect/config.nuon"

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
    let config_items = if ($browsing_path | is-empty) {
        [
            { display: $"(ansi dark_gray)──────────────────────────────────────(ansi reset)", type: "separator", action: "" }
            { display: $"(ansi yellow)⚙(ansi reset)  Sort: (ansi white_bold)($sort_display)(ansi reset)", type: "config", action: "sort" }
            { display: $"(ansi yellow)⚙(ansi reset)  Command: (ansi white_bold)(if ($config.command | is-empty) { '(none)' } else { $config.command })(ansi reset)", type: "config", action: "command" }
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

                    if $tmux {
                        # Open in new tmux window with directory name
                        if ($config.command | is-empty) {
                            tmux new-window -n $selection.name -c $selection.path
                        } else {
                            tmux new-window -n $selection.name -c $selection.path $"nu -e '($config.command)'"
                        }
                    } else {
                        print ""
                        print $"(ansi green)($line)(ansi reset)"
                        print $"(ansi green)  ✓(ansi reset) Selected (ansi white_bold)($selection.name)(ansi reset)"
                        print $"(ansi dark_gray)  → ($selection.path)(ansi reset)"
                        print $"(ansi green)($line)(ansi reset)"
                        cd $selection.path
                        
                        # Run the configured command if set
                        if ($config.command | is-not-empty) {
                            nu -c $config.command
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

                        if $tmux {
                            if ($config.command | is-empty) {
                                tmux new-window -n $selection.name -c $selection.path
                            } else {
                                tmux new-window -n $selection.name -c $selection.path $"nu -e '($config.command)'"
                            }
                        } else {
                            print ""
                            print $"(ansi green)($line)(ansi reset)"
                            print $"(ansi green)  ✓(ansi reset) Selected (ansi white_bold)($selection.name)(ansi reset)"
                            print $"(ansi dark_gray)  → ($selection.path)(ansi reset)"
                            print $"(ansi green)($line)(ansi reset)"
                            cd $selection.path
                            
                            if ($config.command | is-not-empty) {
                                nu -c $config.command
                            }
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
                    "command" => {
                        # Load command history
                        let cmd_history_file = ($"($config.cache_dir)/command_history.nuon" | path expand)
                        let cmd_history = if ($cmd_history_file | path exists) {
                            open $cmd_history_file | default []
                        } else {
                            []
                        }
                        
                        print ""
                        let current = if ($config.command | is-empty) { "" } else { $config.command }
                        let current_display = if ($current | is-empty) { "(none)" } else { $current }
                        print $"(ansi yellow)Current command:(ansi reset) ($current_display)"
                        
                        let new_cmd = if ($cmd_history | is-empty) {
                            # No history - just prompt for input
                            print $"(ansi dark_gray)Enter command, empty for just cd:(ansi reset)"
                            input "Command: "
                        } else {
                            # Show history selection
                            print $"(ansi dark_gray)Select from history or type new:(ansi reset)"
                            print ""
                            
                            let history_items = ($cmd_history | each {|cmd|
                                { display: $"  ($cmd)", value: $cmd, type: "history" }
                            })
                            let menu_items = [
                                { display: $"(ansi yellow)▸(ansi reset) Type new command...", value: "__NEW__", type: "new" }
                                { display: $"(ansi red)✕(ansi reset) Clear command", value: "__CLEAR__", type: "clear" }
                            ] | append $history_items
                            
                            let selection = ($menu_items | input list --display display "Select:")
                            
                            if ($selection | is-empty) {
                                null  # User cancelled
                            } else if $selection.value == "__NEW__" {
                                input "Command: "
                            } else if $selection.value == "__CLEAR__" {
                                ""
                            } else {
                                $selection.value
                            }
                        }
                        
                        if ($new_cmd != null) {
                            # Save to config
                            let new_config = ($config | upsert command $new_cmd)
                            save-config $new_config
                            
                            # Update command history (add new commands, keep unique, limit to 10)
                            if ($new_cmd | is-not-empty) and ($new_cmd not-in $cmd_history) {
                                let updated_history = ([$new_cmd] | append $cmd_history | take 10)
                                $updated_history | save -f $cmd_history_file
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
