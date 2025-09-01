#!/bin/sh
# Access Framework Initialization - Stacker Dependency Loader
# Ensures Access has Stacker framework available before operations

# Detect and load Stacker framework
STACKER_REQUIRED=true
STACKER_MIN_VERSION="2.0.0"

# Try to find Stacker in various locations
detect_stacker_dependency() {
    local stacker_path=""
    
    # Method 1: Check for Stacker in sibling directory (workspace setup)
    if [ -f "../stacker/stacker.sh" ]; then
        stacker_path="../stacker"
    # Method 2: Check for global Stacker installation
    elif command -v stacker >/dev/null 2>&1; then
        stacker_path="global"
    # Method 3: Check standard locations (prioritize system installation)
    elif [ -f "/home/x/stacker/stacker-loader.sh" ]; then
        stacker_path="/home/x/stacker"
    elif [ -f "$HOME/stacker/stacker.sh" ]; then
        stacker_path="$HOME/stacker"
    elif [ -f "/usr/local/lib/stacker/stacker.sh" ]; then
        stacker_path="/usr/local/lib/stacker"
    else
        echo "ERROR: Stacker framework not found" >&2
        echo "Access requires Stacker framework as a dependency" >&2
        echo "" >&2
        echo "Please install Stacker:" >&2
        echo "  git clone https://github.com/akaoio/stacker ~/stacker" >&2
        echo "  cd ~/stacker && ./stacker.sh self-install" >&2
        return 1
    fi
    
    echo "$stacker_path"
    return 0
}

# Load Stacker framework
load_stacker_dependency() {
    local stacker_path
    stacker_path=$(detect_stacker_dependency) || return 1
    
    if [ "$stacker_path" = "global" ]; then
        # Global installation - functions should be available
        if ! command -v stacker >/dev/null 2>&1; then
            echo "ERROR: Global stacker command not working" >&2
            return 1
        fi
        # Set STACKER_GLOBAL flag for bridge
        export STACKER_GLOBAL=true
    else
        # Local installation - source the framework
        export STACKER_DIR="$(cd "$stacker_path" && pwd)"
        if [ ! -f "$stacker_path/stacker-loader.sh" ]; then
            echo "ERROR: Stacker loader not found at $stacker_path" >&2
            return 1
        fi
        
        # Load Stacker framework
        . "$stacker_path/stacker-loader.sh" || {
            echo "ERROR: Failed to load Stacker loader" >&2
            return 1
        }
        
        # Initialize Stacker
        stacker_loader_init || {
            echo "ERROR: Failed to initialize Stacker" >&2
            return 1
        }
        
        # Initialize Access with Stacker
        stacker_init "access" "https://github.com/akaoio/access.git" "access.sh" "Access DNS synchronization service"
    fi
    
    # Verify core Stacker functions are available
    if ! command -v stacker_log >/dev/null 2>&1; then
        echo "ERROR: Stacker core functions not available" >&2
        return 1
    fi
    
    stacker_log "Stacker framework loaded successfully"
    export STACKER_LOADED=true
    return 0
}

# Initialize Access with Stacker dependency
access_init() {
    # Load Stacker as required dependency
    load_stacker_dependency || {
        echo "FATAL: Cannot initialize Access without Stacker framework" >&2
        exit 1
    }
    
    # Load Access-specific modules that are not duplicated in Stacker
    local access_modules="validation advanced wizard"
    for module in $access_modules; do
        if [ -f "modules/${module}.sh" ]; then
            . "modules/${module}.sh" || {
                stacker_error "Failed to load Access module: $module"
                return 1
            }
            stacker_debug "Loaded Access module: $module"
        fi
    done
    
    # Load Stacker bridge for unified interface
    if [ -f "lib/stacker-bridge.sh" ]; then
        . "lib/stacker-bridge.sh" || {
            stacker_error "Failed to load Stacker bridge"
            return 1
        }
        stacker_debug "Stacker bridge loaded"
    fi
    
    stacker_log "Access framework initialized with Stacker dependency"
    return 0
}

# Initialization function available in current shell context