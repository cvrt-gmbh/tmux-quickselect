# default.nu
# Default plugin for tmux-quickselect: Simple command execution
# https://github.com/cvrt-gmbh/tmux-quickselect

# Plugin metadata
export const PLUGIN_NAME = "default"
export const PLUGIN_DESC = "Execute a simple command in the selected directory"
export const PLUGIN_VERSION = "1.0.0"

# Plugin configuration schema
export def default-config [] {
    {
        # Command to run (empty = just open shell)
        command: ""
    }
}

# Main plugin entry point
export def run [
    path: string,           # Selected directory path
    name: string,           # Directory name (for window title)
    plugin_config: record,  # Plugin-specific config
    tmux: bool              # Whether running in tmux mode
] {
    let config = (default-config | merge $plugin_config)
    let cmd = ($config | get -o command | default "")
    
    { 
        command: $cmd
        window_name: $name
    }
}
