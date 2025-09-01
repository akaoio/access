#!/bin/sh
# Access Logging Functions - Standalone Implementation
# Provides basic logging functions for Access when Stacker is not available

# Colors for output (POSIX compliant terminal detection)
if [ "${NO_COLOR:-0}" = "1" ] || [ "${FORCE_COLOR:-0}" = "0" ]; then
    ACCESS_RED=''
    ACCESS_GREEN=''
    ACCESS_YELLOW=''
    ACCESS_BLUE=''
    ACCESS_NC=''
elif [ "${FORCE_COLOR:-0}" = "1" ] || { [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; }; then
    ACCESS_RED='\033[0;31m'
    ACCESS_GREEN='\033[0;32m' 
    ACCESS_YELLOW='\033[1;33m'
    ACCESS_BLUE='\033[0;34m'
    ACCESS_NC='\033[0m'
else
    ACCESS_RED=''
    ACCESS_GREEN=''
    ACCESS_YELLOW=''
    ACCESS_BLUE=''
    ACCESS_NC=''
fi

# Basic logging functions for Access standalone mode
log() {
    if [ -n "$ACCESS_BLUE" ] && echo -e test >/dev/null 2>&1; then
        echo -e "${ACCESS_BLUE}[Access]${ACCESS_NC} $*"
    else
        printf "%s[Access]%s %s\n" "$ACCESS_BLUE" "$ACCESS_NC" "$*"
    fi
}

log_error() {
    if [ -n "$ACCESS_RED" ] && echo -e test >/dev/null 2>&1; then
        echo -e "${ACCESS_RED}[Access ERROR]${ACCESS_NC} $*" >&2
    else
        printf "%s[Access ERROR]%s %s\n" "$ACCESS_RED" "$ACCESS_NC" "$*" >&2
    fi
}

log_warn() {
    if [ -n "$ACCESS_YELLOW" ] && echo -e test >/dev/null 2>&1; then
        echo -e "${ACCESS_YELLOW}[Access WARN]${ACCESS_NC} $*"
    else
        printf "%s[Access WARN]%s %s\n" "$ACCESS_YELLOW" "$ACCESS_NC" "$*"
    fi
}

log_success() {
    if [ -n "$ACCESS_GREEN" ] && echo -e test >/dev/null 2>&1; then
        echo -e "${ACCESS_GREEN}[Access SUCCESS]${ACCESS_NC} $*"
    else
        printf "%s[Access SUCCESS]%s %s\n" "$ACCESS_GREEN" "$ACCESS_NC" "$*"
    fi
}

# Configuration functions for Access standalone mode
ACCESS_CONFIG="${ACCESS_CONFIG:-$HOME/.config/access/config.json}"

load_config() {
    # Create default config if it doesn't exist
    if [ ! -f "$ACCESS_CONFIG" ]; then
        mkdir -p "$(dirname "$ACCESS_CONFIG")"
        echo '{}' > "$ACCESS_CONFIG"
    fi
    
    # Load basic variables if config exists and jq is available
    if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
        PROVIDER=$(jq -r '.provider // "none"' "$ACCESS_CONFIG" 2>/dev/null)
        DOMAIN=$(jq -r '.domain // ""' "$ACCESS_CONFIG" 2>/dev/null)
        HOST=$(jq -r '.host // ""' "$ACCESS_CONFIG" 2>/dev/null)
    fi
}

save_config_value() {
    local key="$1"
    local value="$2"
    
    mkdir -p "$(dirname "$ACCESS_CONFIG")"
    
    # Use jq if available, otherwise create simple config
    if command -v jq >/dev/null 2>&1; then
        local temp_file="/tmp/access_config_$$"
        if [ -f "$ACCESS_CONFIG" ]; then
            jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$ACCESS_CONFIG" > "$temp_file" 2>/dev/null
        else
            jq -n --arg key "$key" --arg value "$value" '{($key): $value}' > "$temp_file" 2>/dev/null
        fi
        
        if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
            mv "$temp_file" "$ACCESS_CONFIG"
        else
            rm -f "$temp_file"
            log_error "Failed to save config value: $key=$value"
        fi
    else
        log_warn "jq not available - config not saved"
    fi
}

# Export marker to indicate this module is loaded
export ACCESS_LOGGING_LOADED=true