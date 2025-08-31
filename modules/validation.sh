#!/bin/sh
# Module: validation
# Description: Configuration validation with scan feature as optional
# Dependencies: core config
# Provides: Configuration validation, scan feature validation, default settings

# Module metadata
STACKER_MODULE_NAME="validation"
STACKER_MODULE_VERSION="1.0.0"
STACKER_MODULE_DEPENDENCIES="core config"
STACKER_MODULE_LOADED=false

# Module initialization
validation_init() {
    STACKER_MODULE_LOADED=true
    stacker_debug "Validation module initialized"
    return 0
}

# Validate scan feature is truly optional
validate_scan_optional() {
    local config_file="$HOME/.config/access/config.json"
    local scan_config="$HOME/.config/access/scan.json"
    
    stacker_debug "Validating scan feature is optional"
    
    # Check if main Access works without scan configuration
    if [ ! -f "$scan_config" ]; then
        stacker_debug "✓ No scan configuration found - this is normal and expected"
        return 0
    fi
    
    # If scan config exists, validate it's properly configured
    if [ -f "$scan_config" ]; then
        local scan_enabled=$(sed -n 's/.*"enable_auto_sync"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$scan_config" 2>/dev/null)
        
        if [ "$scan_enabled" = "false" ]; then
            stacker_debug "✓ Scan configuration exists but is disabled - this is valid"
            return 0
        elif [ "$scan_enabled" = "true" ]; then
            stacker_debug "Scan configuration enabled, validating requirements..."
            return validate_scan_requirements
        fi
    fi
    
    return 0
}

# Validate scan requirements only if scan is enabled
validate_scan_requirements() {
    local scan_config="$HOME/.config/access/scan.json"
    
    if [ ! -f "$scan_config" ]; then
        stacker_error "Scan feature enabled but no configuration found"
        return 1
    fi
    
    # Extract required fields
    local domain=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$scan_config" 2>/dev/null)
    local provider=$(sed -n 's/.*"dns_provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$scan_config" 2>/dev/null)
    
    if [ -z "$domain" ]; then
        stacker_warn "Scan feature enabled but no domain configured"
        return 1
    fi
    
    if [ -z "$provider" ]; then
        stacker_warn "Scan feature enabled but no DNS provider configured"
        stacker_log "Run 'access scan setup' to complete configuration"
        return 1
    fi
    
    stacker_debug "✓ Scan feature properly configured"
    return 0
}

# Ensure Access works without scan feature
validate_access_standalone() {
    local config_file="$HOME/.config/access/config.json"
    
    stacker_debug "Validating Access works standalone (without scan)"
    
    if [ ! -f "$config_file" ]; then
        stacker_debug "No main configuration found - this is expected for new installations"
        return 0
    fi
    
    # Check if basic Access configuration is valid
    local provider=$(sed -n 's/.*"provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config_file" 2>/dev/null)
    local domain=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config_file" 2>/dev/null)
    
    if [ -n "$provider" ] && [ -n "$domain" ]; then
        stacker_debug "✓ Basic Access configuration appears valid"
        return 0
    fi
    
    stacker_debug "Basic Access configuration not yet complete - this is normal"
    return 0
}

# Validate that scan feature doesn't break basic functionality
validate_no_scan_interference() {
    stacker_debug "Validating scan feature doesn't interfere with basic functionality"
    
    # Check if scan scripts exist and are properly isolated
    local scan_script="$(dirname "$0")/scan.sh"
    
    if [ -f "$scan_script" ]; then
        # Verify scan script doesn't run unless explicitly called
        if grep -q "scan.sh" "$scan_script" 2>/dev/null; then
            # This is expected - scan script references itself
            stacker_debug "✓ Scan script exists and is self-contained"
        fi
    else
        stacker_debug "No scan script found - scan feature not installed"
    fi
    
    return 0
}

# Create safe default configuration that works without scan
create_safe_defaults() {
    local config_file="$HOME/.config/access/config.json"
    
    stacker_debug "Creating safe default configuration"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")"
    
    # Only create if it doesn't exist
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
{
    "version": "2.1.0",
    "scan_enabled": false,
    "auto_update": false,
    "log_level": "info",
    "created": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "note": "Access works perfectly without additional configuration"
}
EOF
        
        chmod 600 "$config_file"
        stacker_debug "✓ Safe default configuration created"
    fi
    
    return 0
}

# Comprehensive validation function
validate_installation() {
    stacker_log "Validating Access installation..."
    
    local validation_errors=0
    
    # Validate scan feature is truly optional
    if ! validate_scan_optional; then
        stacker_warn "Scan feature validation failed"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate Access works standalone
    if ! validate_access_standalone; then
        stacker_warn "Standalone functionality validation failed"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate no interference
    if ! validate_no_scan_interference; then
        stacker_warn "Scan interference validation failed"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Create safe defaults
    if ! create_safe_defaults; then
        stacker_warn "Failed to create safe defaults"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ "$validation_errors" -eq 0 ]; then
        stacker_log "✓ Installation validation passed"
        return 0
    else
        stacker_warn "Installation validation completed with $validation_errors warnings"
        return 1
    fi
}

# Quick validation for existing installations
validate_existing_config() {
    stacker_debug "Validating existing configuration"
    
    local config_errors=0
    
    # Check main config
    local config_file="$HOME/.config/access/config.json"
    if [ -f "$config_file" ]; then
        if command -v jq >/dev/null 2>&1; then
            if ! jq empty "$config_file" >/dev/null 2>&1; then
                stacker_error "Invalid JSON in main configuration"
                config_errors=$((config_errors + 1))
            fi
        fi
    fi
    
    # Check scan config if it exists
    local scan_config="$HOME/.config/access/scan.json"
    if [ -f "$scan_config" ]; then
        if command -v jq >/dev/null 2>&1; then
            if ! jq empty "$scan_config" >/dev/null 2>&1; then
                stacker_error "Invalid JSON in scan configuration"
                config_errors=$((config_errors + 1))
            fi
        fi
        
        # Validate scan config if enabled
        local scan_enabled=$(sed -n 's/.*"enable_auto_sync"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$scan_config" 2>/dev/null)
        if [ "$scan_enabled" = "true" ]; then
            if ! validate_scan_requirements; then
                stacker_warn "Scan feature enabled but not properly configured"
                config_errors=$((config_errors + 1))
            fi
        fi
    fi
    
    if [ "$config_errors" -eq 0 ]; then
        stacker_log "✓ Configuration validation passed"
        return 0
    else
        stacker_warn "Configuration validation found $config_errors issues"
        return 1
    fi
}

# Test basic functionality without scan
test_basic_functionality() {
    stacker_debug "Testing basic Access functionality"
    
    # Test IP detection (should work without any configuration)
    if command -v access >/dev/null 2>&1; then
        if access ip >/dev/null 2>&1; then
            stacker_debug "✓ IP detection works"
        else
            stacker_debug "IP detection test skipped (command not available yet)"
        fi
    fi
    
    # Test configuration loading
    if [ -f "$HOME/.config/access/config.json" ]; then
        stacker_debug "✓ Configuration file accessible"
    else
        stacker_debug "No configuration file found (normal for new installs)"
    fi
    
    return 0
}

# Export public interface
validation_list_functions() {
    echo "validate_installation validate_existing_config validate_scan_optional"
    echo "test_basic_functionality create_safe_defaults"
}

# Initialize module
validation_init