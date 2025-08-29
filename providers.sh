#!/bin/sh
# Provider Abstraction Layer - Fully Agnostic Auto-Scan
# No hardcoded provider knowledge - complete runtime scan

PROVIDER_DIR="${PROVIDER_DIR:-$(dirname "$0")/providers}"

# Auto-discover all providers without any hardcoding
discover_providers() {
    [ ! -d "$PROVIDER_DIR" ] && return 1
    
    for provider_file in "$PROVIDER_DIR"/*.sh; do
        [ -f "$provider_file" ] || continue
        echo "$(basename "$provider_file" .sh)"
    done
}

# Extract provider metadata without sourcing
get_provider_metadata() {
    local provider_file="$1"
    local metadata_type="$2"
    
    case "$metadata_type" in
        name)
            # Try to extract name from comments or provider_info
            grep -m1 "^# Name:" "$provider_file" 2>/dev/null | sed 's/^# Name: *//'
            ;;
        description)
            # Try multiple patterns to find description
            grep -m1 "^# Description:\|^# .* Provider\|^# .* DNS\|^# .* Service" "$provider_file" 2>/dev/null | head -1 | sed 's/^# \(Description: \)\?//'
            ;;
        type)
            # Auto-detect provider type from file content
            if grep -q "DNS\|domain\|record" "$provider_file" 2>/dev/null; then
                echo "dns"
            elif grep -q "blockchain\|contract\|web3" "$provider_file" 2>/dev/null; then
                echo "blockchain"
            elif grep -q "ipfs\|distributed\|p2p" "$provider_file" 2>/dev/null; then
                echo "p2p"
            else
                echo "unknown"
            fi
            ;;
        version)
            grep -m1 "^# Version:" "$provider_file" 2>/dev/null | sed 's/^# Version: *//'
            ;;
    esac
}

# List providers with auto-discovered metadata
list_providers() {
    echo "Available providers (auto-discovered):"
    echo ""
    
    for provider in $(discover_providers); do
        provider_file="$PROVIDER_DIR/$provider.sh"
        
        # Get metadata without sourcing
        desc=$(get_provider_metadata "$provider_file" description)
        type=$(get_provider_metadata "$provider_file" type)
        
        if [ -n "$desc" ]; then
            printf "  %-15s [%-10s] %s\n" "$provider" "$type" "$desc"
        else
            printf "  %-15s [%-10s]\n" "$provider" "$type"
        fi
    done
}

# Load provider dynamically with security validation
load_provider() {
    local provider_name="$1"
    
    [ -z "$provider_name" ] && return 1
    
    # SECURITY FIX 1: Input sanitization to prevent command injection
    # Validate provider name contains only safe characters
    case "$provider_name" in
        *[^a-zA-Z0-9_-]*)
            echo "Error: Invalid provider name: $provider_name (only alphanumeric, underscore, hyphen allowed)" >&2
            return 1
            ;;
        ../*|*/../*|*/..|*/../*)
            echo "Error: Path traversal attempt in provider name: $provider_name" >&2
            return 1
            ;;
        /*|~/*|\$*)
            echo "Error: Absolute path or variable expansion attempt in provider name: $provider_name" >&2
            return 1
            ;;
    esac
    
    # Limit provider name length to prevent buffer attacks
    if [ ${#provider_name} -gt 50 ]; then
        echo "Error: Provider name too long: $provider_name (max 50 characters)" >&2
        return 1
    fi
    
    # Find provider file (case-insensitive) with additional security checks
    local provider_file=""
    for file in "$PROVIDER_DIR"/*.sh; do
        [ -f "$file" ] || continue
        
        # Verify file is actually in provider directory (no symlink attacks)
        case "$(readlink -f "$file" 2>/dev/null || realpath "$file" 2>/dev/null || echo "$file")" in
            "$(readlink -f "$PROVIDER_DIR" 2>/dev/null || realpath "$PROVIDER_DIR" 2>/dev/null || echo "$PROVIDER_DIR")"/*.sh)
                # File is safely in provider directory
                ;;
            *)
                echo "Warning: Skipping provider file outside provider directory: $file" >&2
                continue
                ;;
        esac
        
        base=$(basename "$file" .sh)
        if [ "$(echo "$base" | tr '[:upper:]' '[:lower:]')" = "$(echo "$provider_name" | tr '[:upper:]' '[:lower:]')" ]; then
            provider_file="$file"
            break
        fi
    done
    
    if [ -z "$provider_file" ] || [ ! -f "$provider_file" ]; then
        echo "Error: Provider not found: $provider_name" >&2
        echo "Available providers:" >&2
        discover_providers | while read -r p; do
            echo "  - $p" >&2
        done
        return 1
    fi
    
    # SECURITY FIX 1: Validate provider file before sourcing
    # Check file permissions (should not be world-writable)
    if [ -w "$provider_file" ] && [ "$(stat -f "%p" "$provider_file" 2>/dev/null || stat -c "%a" "$provider_file" 2>/dev/null)" != "${provider_perms}" ]; then
        if ls -la "$provider_file" | grep -q '.\{7\}w'; then
            echo "Error: Provider file is world-writable (security risk): $provider_file" >&2
            return 1
        fi
    fi
    
    # Check file size (prevent resource exhaustion)
    file_size=$(wc -c < "$provider_file" 2>/dev/null || echo 0)
    if [ "$file_size" -gt 100000 ]; then  # 100KB limit
        echo "Error: Provider file too large (security risk): $provider_file" >&2
        return 1
    fi
    
    # Basic content validation - must start with shebang and contain required functions
    if ! head -1 "$provider_file" | grep -q '^#!/bin/sh\|^#!/usr/bin/sh\|^#!/bin/dash'; then
        echo "Error: Provider file missing valid shell shebang: $provider_file" >&2
        return 1
    fi
    
    # Source the provider in a controlled way
    . "$provider_file"
    
    # Verify required functions exist
    for func in provider_info provider_config provider_validate provider_update; do
        if ! command -v "$func" >/dev/null 2>&1; then
            echo "Warning: Provider $provider_name missing function: $func" >&2
        fi
    done
    
    return 0
}

# Get provider configuration help
get_provider_config() {
    local provider_name="$1"
    
    load_provider "$provider_name" || return 1
    
    echo "Configuration for $provider_name provider:"
    echo ""
    
    if command -v provider_config >/dev/null 2>&1; then
        provider_config | while IFS= read -r line; do
            echo "  $line"
        done
        echo ""
        echo "Example:"
        echo "  access config $provider_name \\"
        provider_config | while IFS= read -r line; do
            field=$(echo "$line" | sed -n 's/.*field: \([^,]*\).*/\1/p' | xargs)
            required=$(echo "$line" | grep -o "required: true" || true)
            if [ -n "$field" ]; then
                echo "    --$(echo "$field" | tr '_' '-')=VALUE \\"
            fi
        done | sed '$ s/ \\$//'
    else
        echo "  No configuration help available"
    fi
    
    return 0
}

# Get provider capabilities
get_provider_capabilities() {
    local provider_name="$1"
    
    load_provider "$provider_name" || return 1
    
    echo "Provider: $provider_name"
    echo "Capabilities:"
    
    # Check which functions are available
    command -v provider_info >/dev/null 2>&1 && echo "  ✓ Information"
    command -v provider_config >/dev/null 2>&1 && echo "  ✓ Configuration"
    command -v provider_validate >/dev/null 2>&1 && echo "  ✓ Validation"
    command -v provider_update >/dev/null 2>&1 && echo "  ✓ Update"
    command -v provider_test >/dev/null 2>&1 && echo "  ✓ Testing"
    command -v provider_status >/dev/null 2>&1 && echo "  ✓ Status"
    command -v provider_cleanup >/dev/null 2>&1 && echo "  ✓ Cleanup"
}

# Auto-detect provider from domain
suggest_provider() {
    local domain="$1"
    
    echo "Analyzing domain: $domain"
    echo "Checking available providers..."
    
    for provider in $(discover_providers); do
        load_provider "$provider" 2>/dev/null || continue
        
        # Check if provider has a match function
        if command -v provider_matches_domain >/dev/null 2>&1; then
            if provider_matches_domain "$domain"; then
                echo "Suggested provider: $provider"
                return 0
            fi
        fi
    done
    
    echo "No specific provider detected. Showing all available:"
    list_providers
}

# Provider health check
check_provider_health() {
    echo "Provider Health Check"
    echo "===================="
    
    local total=0
    local healthy=0
    
    for provider in $(discover_providers); do
        total=$((total + 1))
        printf "%-20s ... " "$provider"
        
        if load_provider "$provider" >/dev/null 2>&1; then
            # Check required functions
            missing=""
            for func in provider_update provider_validate; do
                command -v "$func" >/dev/null 2>&1 || missing="$missing $func"
            done
            
            if [ -z "$missing" ]; then
                echo "✓ Healthy"
                healthy=$((healthy + 1))
            else
                echo "⚠ Missing:$missing"
            fi
        else
            echo "✗ Failed to load"
        fi
    done
    
    echo ""
    echo "Summary: $healthy/$total providers healthy"
}

# Detect IP type and determine DNS record type
get_record_type() {
    local ip="$1"
    if echo "$ip" | grep -q ':'; then
        echo "AAAA"  # IPv6
    else
        echo "A"     # IPv4
    fi
}

# Update DNS using provider with abstracted record type logic
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
    
    # ABSTRACTION LAYER: Determine record type from IP
    local record_type=$(get_record_type "$ip")
    echo "[$provider_name] Updating $record_type record for $host.$domain with IP: $ip"
    
    # Call provider_update with optional 4th parameter for record type
    # Providers can use it if provided, or auto-detect from IP if not
    provider_update "$domain" "$host" "$ip" "$record_type"
}

# Test provider connectivity
test_provider() {
    local provider_name="${1:-$PROVIDER}"
    
    if [ -z "$provider_name" ]; then
        echo "Error: No provider specified" >&2
        return 1
    fi
    
    echo "Testing provider: $provider_name"
    
    load_provider "$provider_name" || return 1
    
    # Test basic functions exist
    for func in provider_update provider_validate; do
        if ! type "$func" >/dev/null 2>&1; then
            echo "✗ Missing function: $func"
            return 1
        fi
    done
    
    # Test validation
    if provider_validate; then
        echo "✓ Provider validation passed"
    else
        echo "✗ Provider validation failed"
        return 1
    fi
    
    echo "✓ Provider test completed successfully"
}

# Functions are available after sourcing this file
# No need to export in POSIX sh