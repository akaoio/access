#!/bin/sh
# Provider Abstraction Layer
# This file manages loading and executing provider modules

PROVIDER_DIR="${PROVIDER_DIR:-$(dirname "$0")/providers}"
PROVIDER_CACHE=""

# List available providers
list_providers() {
    if [ ! -d "$PROVIDER_DIR" ]; then
        echo "Error: Provider directory not found: $PROVIDER_DIR" >&2
        return 1
    fi
    
    echo "Available providers:"
    
    # Auto-discover providers without hardcoding
    for provider_file in "$PROVIDER_DIR"/*.sh; do
        [ -f "$provider_file" ] || continue
        provider_name=$(basename "$provider_file" .sh)
        
        # Try to extract info quickly without sourcing entire file
        # Look for provider_info function or descriptive comments
        info_line=$(grep -m1 "^# .* Provider$\|^# .* DNS\|^# .* Service" "$provider_file" 2>/dev/null | head -1)
        
        if [ -n "$info_line" ]; then
            # Clean up the comment to get description
            desc=$(echo "$info_line" | sed 's/^# *//')
            printf "  %-15s %s\n" "$provider_name" "$desc"
        else
            # Fallback: just show the provider name
            printf "  %-15s\n" "$provider_name"
        fi
    done
}

# Load a specific provider
load_provider() {
    local provider_name="$1"
    
    if [ -z "$provider_name" ]; then
        echo "Error: Provider name required" >&2
        return 1
    fi
    
    # Convert provider name to lowercase for file lookup
    local provider_file="$PROVIDER_DIR/$(echo "$provider_name" | tr '[:upper:]' '[:lower:]').sh"
    
    if [ ! -f "$provider_file" ]; then
        echo "Error: Provider not found: $provider_name" >&2
        echo "Available providers:" >&2
        list_providers >&2
        return 1
    fi
    
    # Source the provider file
    . "$provider_file"
    
    # Verify required functions exist
    for func in provider_info provider_config provider_validate provider_update; do
        if ! command -v $func >/dev/null 2>&1; then
            echo "Error: Provider $provider_name missing required function: $func" >&2
            return 1
        fi
    done
    
    PROVIDER_CACHE="$provider_name"
    return 0
}

# Execute provider function
execute_provider() {
    local provider_name="$1"
    local function_name="$2"
    shift 2
    
    # Load provider if not cached
    if [ "$PROVIDER_CACHE" != "$provider_name" ]; then
        load_provider "$provider_name" || return 1
    fi
    
    # Check if function exists
    if ! command -v "$function_name" >/dev/null 2>&1; then
        echo "Error: Function $function_name not found in provider $provider_name" >&2
        return 1
    fi
    
    # Execute the function with remaining arguments
    "$function_name" "$@"
}

# Get provider configuration requirements
get_provider_config() {
    local provider_name="$1"
    
    load_provider "$provider_name" || return 1
    
    echo "Configuration for $provider_name provider:"
    provider_config | while IFS=, read -r field_info; do
        echo "  $field_info"
    done
}

# Validate provider configuration
validate_provider() {
    local provider_name="$1"
    
    load_provider "$provider_name" || return 1
    
    provider_validate
}

# Update DNS using provider
update_with_provider() {
    local provider_name="$1"
    local domain="$2"
    local host="$3"
    local ip="$4"
    
    load_provider "$provider_name" || return 1
    
    # Validate configuration first
    if ! provider_validate; then
        echo "Error: Provider validation failed" >&2
        return 1
    fi
    
    # Execute update
    provider_update "$domain" "$host" "$ip"
}

# Test provider connectivity
test_provider() {
    local provider_name="$1"
    
    load_provider "$provider_name" || return 1
    
    if command -v provider_test >/dev/null 2>&1; then
        provider_test
    else
        echo "Provider $provider_name does not support connectivity testing"
        return 1
    fi
}

# Get provider information
info_provider() {
    local provider_name="$1"
    
    load_provider "$provider_name" || return 1
    
    provider_info
}

# Export environment variables for provider
export_provider_env() {
    local provider_name="$1"
    local prefix=$(echo "$provider_name" | tr '[:lower:]' '[:upper:]')
    
    # Export all environment variables with provider prefix
    env | grep "^${prefix}_" | while IFS='=' read -r key value; do
        export "$key=$value"
    done
}