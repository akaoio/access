#!/bin/sh
# Access Configuration Wizard - Standalone Implementation
# Basic functionality for Access configuration management

# Configuration paths
WIZARD_CONFIG="${WIZARD_CONFIG:-$HOME/.config/access/wizard.json}"
WIZARD_STATE="${WIZARD_STATE:-$HOME/.local/share/access/wizard.state}"

# Basic wizard functions
wizard_log() {
    printf "[Access Wizard] %s\n" "$*"
}

wizard_prompt() {
    local prompt="$1"
    local default="$2"
    
    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default"
    else
        printf "%s: " "$prompt"
    fi
}

wizard_read_input() {
    local input
    read -r input
    echo "$input"
}

wizard_reconfigure() {
    wizard_log "Starting Access reconfiguration..."
    
    echo "Access Configuration Wizard"
    echo "============================"
    echo ""
    
    # Create config directory
    mkdir -p "$(dirname "$WIZARD_CONFIG")"
    mkdir -p "$(dirname "$WIZARD_STATE")"
    
    # Basic configuration
    wizard_prompt "Enter your DNS provider (cloudflare, digitalocean, etc.)"
    provider=$(wizard_read_input)
    
    wizard_prompt "Enter your domain name"
    domain=$(wizard_read_input)
    
    wizard_prompt "Enter hostname prefix (will create [prefix].[domain])"
    host_prefix=$(wizard_read_input)
    
    # Save configuration
    if command -v jq >/dev/null 2>&1; then
        cat > "$WIZARD_CONFIG" <<EOF
{
  "provider": "${provider:-none}",
  "domain": "${domain:-}",
  "host_prefix": "${host_prefix:-host}",
  "configured": true,
  "timestamp": "$(date -Iseconds)"
}
EOF
    else
        # Simple format without jq
        cat > "$WIZARD_CONFIG" <<EOF
provider=${provider:-none}
domain=${domain:-}
host_prefix=${host_prefix:-host}
configured=true
EOF
    fi
    
    wizard_log "Configuration saved to $WIZARD_CONFIG"
    wizard_log "You can now use Access for dynamic DNS updates"
    
    return 0
}

wizard_enable_scan() {
    wizard_log "Enabling scan feature..."
    echo "The scan feature allows Access to coordinate with other instances"
    echo "This is an advanced feature for multi-system deployments"
    echo ""
    
    # Create scan config placeholder
    local scan_config="$HOME/.config/access/scan.json"
    mkdir -p "$(dirname "$scan_config")"
    
    if command -v jq >/dev/null 2>&1; then
        cat > "$scan_config" <<EOF
{
  "enabled": true,
  "range": "1-50", 
  "timeout": 30,
  "timestamp": "$(date -Iseconds)"
}
EOF
    else
        cat > "$scan_config" <<EOF
enabled=true
range=1-50
timeout=30
EOF
    fi
    
    wizard_log "Scan feature enabled - configuration saved to $scan_config"
}

wizard_disable_scan() {
    wizard_log "Disabling scan feature..."
    local scan_config="$HOME/.config/access/scan.json"
    
    if [ -f "$scan_config" ]; then
        rm -f "$scan_config"
    fi
    
    wizard_log "Scan feature disabled"
}

wizard_scan_status() {
    local scan_config="$HOME/.config/access/scan.json" 
    
    if [ -f "$scan_config" ]; then
        wizard_log "Scan feature: ENABLED"
        if command -v jq >/dev/null 2>&1; then
            jq . "$scan_config" 2>/dev/null || cat "$scan_config"
        else
            cat "$scan_config"
        fi
    else
        wizard_log "Scan feature: DISABLED"
        echo "Run 'access-wizard scan enable' to enable multi-system coordination"
    fi
}

wizard_help() {
    cat <<EOF
Access Configuration Wizard

Usage: access-wizard [COMMAND] [OPTIONS]

Commands:
  reconfigure, config    Reconfigure Access settings
  scan enable           Enable scan feature for multi-system deployment
  scan disable          Disable scan feature  
  scan status           Show scan feature status
  help, --help          Show this help

Examples:
  access-wizard config          # Interactive configuration
  access-wizard scan enable     # Enable advanced scan feature
  access-wizard scan status     # Check scan feature status

For basic dynamic DNS, you only need 'reconfigure'. 
The scan feature is optional for advanced multi-system coordination.
EOF
}

# Additional wizard functions expected by access-wizard script
wizard_toggle_scan() {
    local scan_config="$HOME/.config/access/scan.json"
    
    if [ -f "$scan_config" ]; then
        wizard_disable_scan
    else
        wizard_enable_scan
    fi
}

wizard_setup_scan_interactive() {
    wizard_log "Interactive scan setup..."
    wizard_enable_scan
}

wizard_configure_scan() {
    wizard_scan_status
}

wizard_configure_automation() {
    wizard_log "Automation configuration is not yet implemented in standalone mode"
    wizard_log "This feature requires the full Stacker integration"
}

wizard_configure_interval() {
    wizard_log "Interval configuration is not yet implemented in standalone mode"
    wizard_log "This feature requires the full Stacker integration" 
}

wizard_configure_auto_update() {
    wizard_log "Auto-update configuration is not yet implemented in standalone mode"
    wizard_log "This feature requires the full Stacker integration"
}

wizard_apply_changes() {
    wizard_log "Applying configuration changes..."
    wizard_log "Standalone mode - changes are applied immediately"
}

wizard_show_status() {
    wizard_log "Access Configuration Status"
    echo "============================"
    
    if [ -f "$WIZARD_CONFIG" ]; then
        echo "Main config: CONFIGURED"
        if command -v jq >/dev/null 2>&1; then
            jq . "$WIZARD_CONFIG" 2>/dev/null || cat "$WIZARD_CONFIG"
        else
            cat "$WIZARD_CONFIG"
        fi
    else
        echo "Main config: NOT CONFIGURED"
        echo "Run 'access-wizard config' to configure"
    fi
    
    echo ""
    wizard_scan_status
}

# Alias for compatibility with access-wizard script
wizard_status() {
    wizard_show_status
}

# Functions are now loaded and available in the sourcing shell
# Note: export -f is bash-specific, so we rely on sourcing for function availability