#!/bin/sh
# Stacker Bridge - Bidirectional Architecture Support
# Allows Access to work standalone OR with Stacker enhancement
# This creates a clean abstraction layer between Access and Stacker

# Detection flags
STACKER_AVAILABLE=false
STACKER_MODE="standalone"
STACKER_FEATURES=""

# Detect Stacker availability and capabilities
detect_stacker() {
    # Method 1: Check if Stacker is already loaded (when Access is used as Stacker package)
    if [ -n "$STACKER_VERSION" ] && command -v stacker_log >/dev/null 2>&1; then
        STACKER_AVAILABLE=true
        STACKER_MODE="integrated"
        STACKER_FEATURES="full"
        return 0
    fi
    
    # Method 2: Check for Stacker as git submodule
    if [ -d "./stacker" ] && [ -f "./stacker/stacker.sh" ]; then
        STACKER_AVAILABLE=true
        STACKER_MODE="submodule"
        STACKER_DIR="./stacker"
        return 0
    fi
    
    # Method 3: Check for Stacker in parent directory (when Access is submodule)
    if [ -d "../stacker" ] && [ -f "../stacker/stacker.sh" ]; then
        STACKER_AVAILABLE=true
        STACKER_MODE="sibling"
        STACKER_DIR="../stacker"
        return 0
    fi
    
    # Method 4: Check for global Stacker installation
    if command -v stacker >/dev/null 2>&1; then
        STACKER_AVAILABLE=true
        STACKER_MODE="global"
        return 0
    fi
    
    # Method 5: Check for Stacker in well-known locations
    for loc in "$HOME/stacker" "$HOME/.local/lib/stacker" "/usr/local/lib/stacker"; do
        if [ -d "$loc" ] && [ -f "$loc/stacker.sh" ]; then
            STACKER_AVAILABLE=true
            STACKER_MODE="library"
            STACKER_DIR="$loc"
            return 0
        fi
    done
    
    # Method 6: Check if we're running inside a Stacker-managed environment
    if [ -f "../stacker.yaml" ] || [ -f "../../stacker.yaml" ]; then
        # We might be inside a Stacker project
        STACKER_MODE="managed"
        # Try to find Stacker
        if [ -f "../.stacker/stacker.sh" ]; then
            STACKER_AVAILABLE=true
            STACKER_DIR="../.stacker"
            return 0
        fi
    fi
    
    # No Stacker found - standalone mode
    STACKER_MODE="standalone"
    return 1
}

# Load Stacker if available (but don't fail if not)
load_stacker_optional() {
    if [ "$STACKER_AVAILABLE" = true ] && [ "$STACKER_MODE" != "integrated" ]; then
        case "$STACKER_MODE" in
            submodule|sibling|library)
                if [ -f "$STACKER_DIR/stacker.sh" ]; then
                    . "$STACKER_DIR/stacker.sh" 2>/dev/null || true
                    # Check if loading was successful
                    if command -v stacker_log >/dev/null 2>&1; then
                        STACKER_FEATURES="full"
                    fi
                fi
                ;;
            global)
                # Global stacker might be a wrapper script
                STACKER_FEATURES="commands"
                ;;
        esac
    else
        # Load standalone Access logging functions when Stacker is not available
        local bridge_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
        local access_logging_path="$bridge_dir/access-logging.sh"
        [ -f "$access_logging_path" ] && . "$access_logging_path" 2>/dev/null || true
    fi
}

# ============================================================================
# ABSTRACTION LAYER - These functions adapt between Stacker and Access
# ============================================================================

# Unified logging that works standalone or with Stacker
unified_log() {
    local message="$1"
    local level="${2:-info}"
    
    if [ "$STACKER_AVAILABLE" = true ] && command -v stacker_log >/dev/null 2>&1; then
        # Use Stacker's logging
        case "$level" in
            error) stacker_error "$message" ;;
            warn) stacker_warn "$message" ;;
            success) stacker_info "$message" ;;
            *) stacker_log "$message" ;;
        esac
    else
        # Use Access's existing logging functions (no duplication)
        case "$level" in
            error) log_error "$message" ;;
            warn) log_warn "$message" ;;
            success) log_success "$message" ;;
            *) log "$message" ;;
        esac
    fi
}

# Unified configuration that works standalone or with Stacker
unified_config_get() {
    local key="$1"
    
    if [ "$STACKER_AVAILABLE" = true ] && command -v stacker_require >/dev/null 2>&1; then
        # Use Stacker's config system (requires config module)
        stacker_require "config" >/dev/null 2>&1 && stacker_get_config "$key" 2>/dev/null
    else
        # Use Access's existing config functions (no duplication)
        load_config
        case "$key" in
            provider) echo "$PROVIDER" ;;
            domain) echo "$DOMAIN" ;;
            host) echo "$HOST" ;;
            *) 
                # Fallback to JSON parsing for other keys
                if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
                    jq -r ".$key // empty" "$ACCESS_CONFIG" 2>/dev/null
                fi
                ;;
        esac
    fi
}

unified_config_set() {
    local key="$1"
    local value="$2"
    
    if [ "$STACKER_AVAILABLE" = true ] && command -v stacker_require >/dev/null 2>&1; then
        # Use Stacker's config system (requires config module)
        stacker_require "config" >/dev/null 2>&1 && stacker_save_config "$key" "$value" 2>/dev/null
    else
        # Use Access's existing save_config function (no duplication)
        save_config_value "$key" "$value"
    fi
}

# ============================================================================
# CAPABILITY REPORTING
# ============================================================================

report_capabilities() {
    echo "Access Capability Report:"
    echo "========================"
    echo ""
    echo "Stacker Integration:"
    echo "  Available: $STACKER_AVAILABLE"
    echo "  Mode: $STACKER_MODE"
    echo "  Features: ${STACKER_FEATURES:-none}"
    echo ""
    echo "Available Features:"
    
    if [ "$STACKER_AVAILABLE" = true ]; then
        echo "  ✓ Advanced service management (via Stacker)"
        echo "  ✓ Unified configuration system (via Stacker)"
        echo "  ✓ Package management (via Stacker)"
        echo "  ✓ Modular architecture (via Stacker)"
        echo "  ✓ Health monitoring (via Stacker)"
    else
        echo "  ✓ Basic service management (standalone)"
        echo "  ✓ JSON configuration (standalone)"
        echo "  ✓ Manual installation (standalone)"
        echo "  ✓ Simple health checks (standalone)"
    fi
    
    echo ""
    echo "Mode Details:"
    case "$STACKER_MODE" in
        integrated)
            echo "  Running as Stacker package - full integration"
            ;;
        submodule)
            echo "  Stacker found as git submodule - enhanced features"
            ;;
        sibling)
            echo "  Stacker found as sibling project - shared features"
            ;;
        global)
            echo "  Global Stacker installation - command integration"
            ;;
        library)
            echo "  Stacker library found at: $STACKER_DIR"
            ;;
        managed)
            echo "  Inside Stacker-managed project - managed mode"
            ;;
        standalone)
            echo "  Pure standalone mode - no Stacker dependency"
            echo ""
            echo "  To enable Stacker features, you can:"
            echo "    1. Install Stacker: git clone https://github.com/akaoio/stacker ~/stacker"
            echo "    2. Add as submodule: git submodule add https://github.com/akaoio/stacker stacker"
            echo "    3. Install globally: curl -sSL https://stacker.akao.io/install | sh"
            ;;
    esac
}

# Initialize the bridge
detect_stacker
load_stacker_optional

# Export the unified interface
export STACKER_BRIDGE_LOADED=true
export STACKER_AVAILABLE
export STACKER_MODE
export STACKER_FEATURES