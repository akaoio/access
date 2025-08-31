#!/bin/sh
# Module: wizard
# Description: Interactive installation wizard with scan feature as optional
# Dependencies: core config
# Provides: User-friendly installation, scan feature management, configuration toggle

# Module metadata
STACKER_MODULE_NAME="wizard"
STACKER_MODULE_VERSION="1.0.0"
STACKER_MODULE_DEPENDENCIES="core config"
STACKER_MODULE_LOADED=false

# Module initialization
wizard_init() {
    STACKER_MODULE_LOADED=true
    stacker_debug "Wizard module initialized"
    return 0
}

# Configuration paths
WIZARD_CONFIG="${WIZARD_CONFIG:-$HOME/.config/access/wizard.json}"
WIZARD_STATE="${WIZARD_STATE:-$HOME/.local/share/access/wizard.state}"

# Wizard utility functions
wizard_log() {
    printf "[Wizard] %s\n" "$*"
}

wizard_prompt() {
    local prompt="$1"
    local default="$2"
    local value
    
    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default"
    else
        printf "%s: " "$prompt"
    fi
    
    read -r value
    echo "${value:-$default}"
}

wizard_yes_no() {
    local prompt="$1"
    local default="$2"
    local response
    
    case "$default" in
        [Yy]*)
            printf "%s [Y/n]: " "$prompt"
            ;;
        [Nn]*)
            printf "%s [y/N]: " "$prompt"
            ;;
        *)
            printf "%s [y/n]: " "$prompt"
            ;;
    esac
    
    read -r response
    response="${response:-$default}"
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Load wizard configuration
wizard_load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Simple JSON extraction for wizard settings
    WIZARD_AUTOMATION=$(sed -n 's/.*"automation"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config_file" 2>/dev/null)
    WIZARD_SCAN_ENABLED=$(sed -n 's/.*"scan_enabled"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$config_file" 2>/dev/null)
    WIZARD_UPDATE_INTERVAL=$(sed -n 's/.*"update_interval"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$config_file" 2>/dev/null)
    WIZARD_AUTO_UPDATE=$(sed -n 's/.*"auto_update"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$config_file" 2>/dev/null)
    
    return 0
}

# Save wizard configuration
wizard_save_config() {
    local config_file="$1"
    local automation="$2"
    local scan_enabled="$3"
    local update_interval="$4"
    local auto_update="$5"
    
    wizard_log "Saving wizard configuration..."
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")"
    
    # Create configuration JSON
    cat > "$config_file" << EOF
{
    "automation": "$automation",
    "scan_enabled": $scan_enabled,
    "update_interval": $update_interval,
    "auto_update": $auto_update,
    "last_updated": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "wizard_version": "1.0.0"
}
EOF
    
    chmod 600 "$config_file"
    wizard_log "Configuration saved to $config_file"
}

# Quick reconfiguration for existing installations
wizard_reconfigure() {
    wizard_log "Access Configuration Manager"
    echo "===================================="
    echo ""
    
    # Load existing configuration
    if wizard_load_config "$WIZARD_CONFIG"; then
        echo "Current Configuration:"
        printf "  Automation:      %s\n" "${WIZARD_AUTOMATION:-manual}"
        printf "  Scan Feature:    %s\n" "$([ "$WIZARD_SCAN_ENABLED" = "true" ] && echo "ENABLED" || echo "DISABLED")"
        printf "  Update Interval: %s minutes\n" "${WIZARD_UPDATE_INTERVAL:-5}"
        printf "  Auto-Updates:    %s\n" "$([ "$WIZARD_AUTO_UPDATE" = "true" ] && echo "ENABLED" || echo "DISABLED")"
        echo ""
    else
        wizard_log "No existing configuration found"
        echo ""
    fi
    
    # Allow changing individual settings
    echo "What would you like to change?"
    echo "1) Automation method (systemd/cron/manual)"
    echo "2) Scan/peer discovery feature"  
    echo "3) Update interval"
    echo "4) Auto-update settings"
    echo "5) Complete reconfiguration"
    echo "0) Cancel"
    echo ""
    
    choice=$(wizard_prompt "Choice" "0")
    
    case "$choice" in
        1)
            wizard_configure_automation
            ;;
        2)
            wizard_configure_scan
            ;;
        3)
            wizard_configure_interval
            ;;
        4)
            wizard_configure_auto_update
            ;;
        5)
            wizard_full_reconfigure
            ;;
        0|"")
            wizard_log "Configuration cancelled"
            return 0
            ;;
        *)
            wizard_log "Invalid choice"
            return 1
            ;;
    esac
}

# Configure automation method
wizard_configure_automation() {
    echo ""
    echo "Automation Method Configuration:"
    echo "──────────────────────────────"
    echo ""
    
    # Check what's available on the system
    local has_systemd=false
    local has_cron=false
    
    if command -v systemctl >/dev/null 2>&1; then
        has_systemd=true
    fi
    
    if command -v crontab >/dev/null 2>&1; then
        has_cron=true
    fi
    
    echo "Available options:"
    option_num=1
    
    if [ "$has_systemd" = true ] && [ "$has_cron" = true ]; then
        echo "${option_num}) Redundant (systemd + cron) - Maximum reliability"
        option_num=$((option_num + 1))
    fi
    
    if [ "$has_systemd" = true ]; then
        echo "${option_num}) Systemd service - Modern service management"
        option_num=$((option_num + 1))
    fi
    
    if [ "$has_cron" = true ]; then
        echo "${option_num}) Cron job - Traditional scheduled execution"
        option_num=$((option_num + 1))
    fi
    
    echo "${option_num}) Manual - Run Access commands when needed"
    echo ""
    
    choice=$(wizard_prompt "Choice" "1")
    
    # Map choice to automation method
    new_automation="manual"
    case "$choice" in
        1)
            if [ "$has_systemd" = true ] && [ "$has_cron" = true ]; then
                new_automation="redundant"
            elif [ "$has_systemd" = true ]; then
                new_automation="systemd"
            elif [ "$has_cron" = true ]; then
                new_automation="cron"
            fi
            ;;
        2)
            if [ "$has_systemd" = true ] && [ "$has_cron" = true ]; then
                new_automation="systemd"
            elif [ "$has_cron" = true ]; then
                new_automation="cron"
            fi
            ;;
        3)
            if [ "$has_systemd" = true ] && [ "$has_cron" = true ]; then
                new_automation="cron"
            fi
            ;;
    esac
    
    wizard_log "Automation method changed to: $new_automation"
    
    # Update configuration
    WIZARD_AUTOMATION="$new_automation"
    wizard_save_config "$WIZARD_CONFIG" "$WIZARD_AUTOMATION" "${WIZARD_SCAN_ENABLED:-false}" "${WIZARD_UPDATE_INTERVAL:-5}" "${WIZARD_AUTO_UPDATE:-false}"
    
    # Apply changes - this would need to call install.sh with appropriate flags
    wizard_log "To apply changes, run: access-wizard apply-changes"
}

# Configure scan feature (the key function for optional scan)
wizard_configure_scan() {
    echo ""
    echo "Scan/Peer Discovery Feature Configuration:"
    echo "───────────────────────────────────────"
    echo ""
    
    echo "Current status: $([ "$WIZARD_SCAN_ENABLED" = "true" ] && echo "ENABLED" || echo "DISABLED")"
    echo ""
    
    echo "About Scan/Peer Discovery:"
    echo "• OPTIONAL feature for advanced multi-system deployments"
    echo "• Creates peer network (peer0.domain.com, peer1.domain.com, etc.)"
    echo "• Enables automatic coordination between Access instances"
    echo "• Requires DNS provider API credentials"
    echo "• NOT needed for basic dynamic DNS functionality"
    echo ""
    
    if [ "$WIZARD_SCAN_ENABLED" = "true" ]; then
        echo "Scan feature is currently ENABLED."
        echo ""
        if wizard_yes_no "Disable scan/peer discovery" "n"; then
            wizard_disable_scan
        else
            wizard_log "Scan feature remains enabled"
            if wizard_yes_no "Reconfigure scan settings" "n"; then
                wizard_setup_scan_interactive
            fi
        fi
    else
        echo "Scan feature is currently DISABLED."
        echo ""
        echo "Consider enabling if you:"
        echo "• Have multiple servers/systems running Access"
        echo "• Want automatic load balancing across IPs"  
        echo "• Need advanced peer coordination"
        echo ""
        echo "Keep disabled if you:"
        echo "• Have a single system setup"
        echo "• Want simple dynamic DNS functionality"
        echo "• Don't need multi-system coordination"
        echo ""
        
        if wizard_yes_no "Enable scan/peer discovery" "n"; then
            wizard_enable_scan
        else
            wizard_log "Scan feature remains disabled"
        fi
    fi
}

# Enable scan feature
wizard_enable_scan() {
    wizard_log "Enabling scan/peer discovery feature..."
    
    WIZARD_SCAN_ENABLED="true"
    wizard_save_config "$WIZARD_CONFIG" "${WIZARD_AUTOMATION:-manual}" "$WIZARD_SCAN_ENABLED" "${WIZARD_UPDATE_INTERVAL:-5}" "${WIZARD_AUTO_UPDATE:-false}"
    
    wizard_log "Scan feature enabled"
    echo ""
    echo "Next steps:"
    echo "1. Configure scan settings: access scan setup"
    echo "2. Test peer discovery: access scan discover"
    echo "3. Apply configuration: access-wizard apply-changes"
}

# Disable scan feature
wizard_disable_scan() {
    wizard_log "Disabling scan/peer discovery feature..."
    
    WIZARD_SCAN_ENABLED="false"
    wizard_save_config "$WIZARD_CONFIG" "${WIZARD_AUTOMATION:-manual}" "$WIZARD_SCAN_ENABLED" "${WIZARD_UPDATE_INTERVAL:-5}" "${WIZARD_AUTO_UPDATE:-false}"
    
    # Clean up scan configuration
    SCAN_CONFIG="$HOME/.config/access/scan.json"
    if [ -f "$SCAN_CONFIG" ]; then
        if wizard_yes_no "Remove existing scan configuration" "y"; then
            rm -f "$SCAN_CONFIG"
            wizard_log "Scan configuration removed"
        fi
    fi
    
    wizard_log "Scan feature disabled"
    echo ""
    echo "Access will work normally without scan functionality"
    echo "You can re-enable it anytime with: access-wizard reconfigure"
}

# Interactive scan setup
wizard_setup_scan_interactive() {
    echo ""
    echo "Scan Feature Setup:"
    echo "─────────────────"
    echo ""
    
    # Get or confirm domain
    local current_domain=""
    ACCESS_CONFIG="$HOME/.config/access/config.json"
    
    if [ -f "$ACCESS_CONFIG" ]; then
        if command -v jq >/dev/null 2>&1; then
            current_domain=$(jq -r '.domain // ""' "$ACCESS_CONFIG" 2>/dev/null)
        else
            current_domain=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ACCESS_CONFIG" 2>/dev/null)
        fi
    fi
    
    if [ -n "$current_domain" ]; then
        scan_domain=$(wizard_prompt "Domain for peer network" "$current_domain")
    else
        scan_domain=$(wizard_prompt "Domain for peer network (e.g., example.com)" "")
    fi
    
    scan_prefix=$(wizard_prompt "Peer hostname prefix" "peer")
    
    echo ""
    echo "DNS Provider Configuration:"
    echo "1) GoDaddy"
    echo "2) Cloudflare"  
    echo "3) DigitalOcean"
    echo "4) Configure later"
    echo ""
    
    provider_choice=$(wizard_prompt "Choice" "4")
    
    case "$provider_choice" in
        1)
            scan_provider="godaddy"
            echo "Enter GoDaddy API credentials:"
            scan_key=$(wizard_prompt "API Key" "")
            scan_secret=$(wizard_prompt "API Secret" "")
            ;;
        2)
            scan_provider="cloudflare"
            echo "Enter Cloudflare API credentials:"
            scan_email=$(wizard_prompt "Email" "")
            scan_key=$(wizard_prompt "API Key" "")
            scan_zone_id=$(wizard_prompt "Zone ID" "")
            scan_secret=""
            ;;
        3)
            scan_provider="digitalocean"
            echo "Enter DigitalOcean API credentials:"
            scan_key=$(wizard_prompt "API Token" "")
            scan_secret=""
            ;;
        4|*)
            wizard_log "Provider configuration skipped - you can configure it later"
            scan_provider=""
            scan_key=""
            scan_secret=""
            ;;
    esac
    
    # Save scan configuration
    SCAN_CONFIG="$HOME/.config/access/scan.json"
    mkdir -p "$(dirname "$SCAN_CONFIG")"
    
    cat > "$SCAN_CONFIG" << EOF
{
    "domain": "$scan_domain",
    "host_prefix": "$scan_prefix",
    "dns_provider": "$scan_provider",
    "dns_key": "${scan_key:-}",
    "dns_secret": "${scan_secret:-}",
    "enable_auto_sync": true,
    "last_updated": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
    
    chmod 600 "$SCAN_CONFIG"
    wizard_log "Scan configuration saved"
    
    echo ""
    echo "Scan feature is now configured!"
    echo "Test with: access scan discover"
}

# Configure update interval
wizard_configure_interval() {
    echo ""
    echo "Update Interval Configuration:"
    echo "────────────────────────────"
    echo ""
    
    current_interval="${WIZARD_UPDATE_INTERVAL:-5}"
    echo "Current interval: $current_interval minutes"
    echo ""
    
    echo "Recommended intervals:"
    echo "• 1-3 minutes:  High-change environments, complex networks"
    echo "• 5 minutes:    Balanced for most situations"  
    echo "• 10+ minutes:  Stable environments, low system load"
    echo ""
    
    new_interval=$(wizard_prompt "New interval in minutes" "$current_interval")
    
    if [ "$new_interval" -gt 0 ] 2>/dev/null; then
        WIZARD_UPDATE_INTERVAL="$new_interval"
        wizard_save_config "$WIZARD_CONFIG" "${WIZARD_AUTOMATION:-manual}" "${WIZARD_SCAN_ENABLED:-false}" "$WIZARD_UPDATE_INTERVAL" "${WIZARD_AUTO_UPDATE:-false}"
        wizard_log "Update interval changed to $new_interval minutes"
        wizard_log "To apply changes, run: access-wizard apply-changes"
    else
        wizard_log "Invalid interval, keeping current setting"
    fi
}

# Configure auto-update
wizard_configure_auto_update() {
    echo ""
    echo "Auto-Update Configuration:"
    echo "────────────────────────"
    echo ""
    
    current_auto="${WIZARD_AUTO_UPDATE:-false}"
    echo "Current setting: $([ "$current_auto" = "true" ] && echo "ENABLED" || echo "DISABLED")"
    echo ""
    
    if [ "$current_auto" = "true" ]; then
        if wizard_yes_no "Disable automatic updates" "n"; then
            WIZARD_AUTO_UPDATE="false"
            wizard_log "Auto-updates disabled"
        fi
    else
        echo "Auto-updates provide:"
        echo "• Latest security fixes"
        echo "• New features and improvements"
        echo "• Provider API compatibility updates"
        echo ""
        
        if wizard_yes_no "Enable automatic updates" "n"; then
            WIZARD_AUTO_UPDATE="true"
            wizard_log "Auto-updates enabled"
        fi
    fi
    
    wizard_save_config "$WIZARD_CONFIG" "${WIZARD_AUTOMATION:-manual}" "${WIZARD_SCAN_ENABLED:-false}" "${WIZARD_UPDATE_INTERVAL:-5}" "$WIZARD_AUTO_UPDATE"
    wizard_log "To apply changes, run: access-wizard apply-changes"
}

# Full reconfiguration - runs the interactive installer again
wizard_full_reconfigure() {
    wizard_log "Starting full reconfiguration..."
    echo ""
    
    if wizard_yes_no "This will reconfigure all Access settings. Continue" "n"; then
        # Check if interactive installer exists
        if [ -x "./interactive-install.sh" ]; then
            wizard_log "Starting interactive installation wizard..."
            exec ./interactive-install.sh
        elif [ -x "$(command -v access-wizard)" ]; then
            wizard_log "Starting access wizard..."
            exec access-wizard
        else
            wizard_log "Interactive installer not found. Manual configuration required."
            echo ""
            echo "Manual configuration commands:"
            echo "access config <provider> --key=KEY --domain=DOMAIN"
            echo "access scan setup  # If you want scan feature"
        fi
    else
        wizard_log "Full reconfiguration cancelled"
    fi
}

# Apply configuration changes
wizard_apply_changes() {
    wizard_log "Applying configuration changes..."
    
    if ! wizard_load_config "$WIZARD_CONFIG"; then
        wizard_log "No wizard configuration found"
        return 1
    fi
    
    # Build install.sh arguments based on configuration
    install_args=""
    
    case "$WIZARD_AUTOMATION" in
        redundant)
            install_args="$install_args --redundant"
            ;;
        systemd)
            install_args="$install_args --service-only"
            ;;
        cron)
            install_args="$install_args --cron-only --interval=${WIZARD_UPDATE_INTERVAL:-5}"
            ;;
        manual)
            install_args="$install_args --manual-only"
            ;;
    esac
    
    [ "$WIZARD_AUTO_UPDATE" = "true" ] && install_args="$install_args --auto-update"
    [ "$WIZARD_SCAN_ENABLED" = "true" ] && install_args="$install_args --scan"
    
    install_args="$install_args --non-interactive"
    
    wizard_log "Running: ./install.sh $install_args"
    
    if ./install.sh $install_args; then
        wizard_log "Configuration changes applied successfully"
        return 0
    else
        wizard_log "Failed to apply configuration changes"
        return 1
    fi
}

# Show wizard status
wizard_status() {
    echo "Access Configuration Status:"
    echo "============================"
    echo ""
    
    if wizard_load_config "$WIZARD_CONFIG"; then
        printf "Automation Method:    %s\n" "${WIZARD_AUTOMATION:-not configured}"
        printf "Scan Feature:         %s\n" "$([ "$WIZARD_SCAN_ENABLED" = "true" ] && echo "ENABLED" || echo "DISABLED")"
        printf "Update Interval:      %s minutes\n" "${WIZARD_UPDATE_INTERVAL:-not configured}"
        printf "Auto-Updates:         %s\n" "$([ "$WIZARD_AUTO_UPDATE" = "true" ] && echo "ENABLED" || echo "DISABLED")"
        echo ""
        
        # Show scan configuration details if enabled
        if [ "$WIZARD_SCAN_ENABLED" = "true" ]; then
            SCAN_CONFIG="$HOME/.config/access/scan.json"
            if [ -f "$SCAN_CONFIG" ]; then
                echo "Scan Configuration:"
                scan_domain=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
                scan_prefix=$(sed -n 's/.*"host_prefix"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
                scan_provider=$(sed -n 's/.*"dns_provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
                
                printf "  Domain:             %s\n" "${scan_domain:-not configured}"
                printf "  Prefix:             %s\n" "${scan_prefix:-peer}"
                printf "  DNS Provider:       %s\n" "${scan_provider:-not configured}"
            else
                echo "  Configuration:      Not found - run 'access scan setup'"
            fi
        fi
    else
        echo "No configuration found."
        echo "Run 'access-wizard' to create initial configuration."
    fi
    echo ""
}

# Toggle scan feature on/off easily
wizard_toggle_scan() {
    if ! wizard_load_config "$WIZARD_CONFIG"; then
        wizard_log "No configuration found. Run 'access-wizard' first."
        return 1
    fi
    
    if [ "$WIZARD_SCAN_ENABLED" = "true" ]; then
        echo "Scan feature is currently ENABLED"
        if wizard_yes_no "Disable scan feature" "n"; then
            wizard_disable_scan
            wizard_apply_changes
        fi
    else
        echo "Scan feature is currently DISABLED"  
        if wizard_yes_no "Enable scan feature" "n"; then
            wizard_enable_scan
            if wizard_yes_no "Configure scan settings now" "y"; then
                wizard_setup_scan_interactive
            fi
            wizard_apply_changes
        fi
    fi
}

# Export public interface
wizard_list_functions() {
    echo "wizard_reconfigure wizard_configure_scan wizard_toggle_scan"
    echo "wizard_status wizard_apply_changes wizard_enable_scan wizard_disable_scan"
    echo "wizard_configure_automation wizard_configure_interval wizard_configure_auto_update"
}

# Initialize module
wizard_init