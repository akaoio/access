#!/bin/sh
# Access Uninstaller - Complete removal of Access DNS synchronization
# Removes all traces: binary, configs, cron jobs, systemd service

set -e

# Configuration
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
SCRIPT_NAME="access"
ACCESS_HOME="${ACCESS_HOME:-$HOME/.access}"
SERVICE_NAME="access.service"

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

log() {
    echo "${GREEN}[Access Uninstaller]${NC} $*"
}

warn() {
    echo "${YELLOW}[Warning]${NC} $*"
}

error() {
    echo "${RED}[Error]${NC} $*" >&2
}

# Display header
show_header() {
    echo "=================================================="
    echo "  Access DNS Synchronization - Uninstaller"
    echo "  This will remove Access completely"
    echo "=================================================="
    echo ""
}

# Confirm uninstall
confirm_uninstall() {
    if [ "$1" != "--force" ] && [ "$1" != "-f" ]; then
        printf "Are you sure you want to uninstall Access? This will remove:\n"
        printf "  - Binary from %s\n" "$INSTALL_DIR/$SCRIPT_NAME"
        printf "  - Configuration from %s\n" "$ACCESS_HOME"
        printf "  - Cron jobs\n"
        printf "  - Systemd service (if exists)\n"
        printf "\nType 'yes' to continue: "
        read -r response
        
        if [ "$response" != "yes" ]; then
            log "Uninstall cancelled"
            exit 1
        fi
    fi
}

# Remove binary
remove_binary() {
    local binary_path="$INSTALL_DIR/$SCRIPT_NAME"
    
    if [ -f "$binary_path" ]; then
        log "Removing binary: $binary_path"
        
        if [ -w "$INSTALL_DIR" ]; then
            rm -f "$binary_path"
        else
            log "Requesting sudo to remove binary..."
            sudo rm -f "$binary_path"
        fi
        
        log "✓ Binary removed"
    else
        warn "Binary not found at $binary_path"
    fi
    
    # Also check for backup
    if [ -f "$binary_path.backup" ]; then
        log "Removing backup: $binary_path.backup"
        if [ -w "$INSTALL_DIR" ]; then
            rm -f "$binary_path.backup"
        else
            sudo rm -f "$binary_path.backup"
        fi
    fi
}

# Remove cron jobs
remove_cron() {
    if command -v crontab >/dev/null 2>&1; then
        log "Removing cron jobs..."
        
        # Remove access-related cron entries
        local temp_cron="/tmp/cron_uninstall_$$"
        crontab -l 2>/dev/null | grep -v "$SCRIPT_NAME" | grep -v "access" > "$temp_cron" 2>/dev/null || true
        
        # Only update crontab if there are changes
        if [ -s "$temp_cron" ]; then
            crontab "$temp_cron"
        else
            # If crontab is now empty, remove it
            crontab -r 2>/dev/null || true
        fi
        
        rm -f "$temp_cron"
        log "✓ Cron jobs removed"
    else
        warn "Cron not available on this system"
    fi
}

# Remove systemd service
remove_systemd() {
    if command -v systemctl >/dev/null 2>&1; then
        if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
            log "Removing systemd service..."
            
            # Stop service
            sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            
            # Disable service
            sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            
            # Remove service file
            sudo rm -f "/etc/systemd/system/$SERVICE_NAME"
            
            # Reload systemd
            sudo systemctl daemon-reload
            
            log "✓ Systemd service removed"
        else
            warn "Systemd service not found"
        fi
    fi
}

# Remove configuration and data
remove_config() {
    if [ -d "$ACCESS_HOME" ]; then
        log "Removing configuration directory: $ACCESS_HOME"
        
        # Backup config before removing (just in case)
        if [ -f "$ACCESS_HOME/config.json" ]; then
            cp "$ACCESS_HOME/config.json" "/tmp/access_config_backup_$(date +%Y%m%d_%H%M%S).json" 2>/dev/null || true
            log "Config backed up to /tmp/"
        fi
        
        rm -rf "$ACCESS_HOME"
        log "✓ Configuration removed"
    else
        warn "Configuration directory not found"
    fi
}

# Remove auto-update script
remove_auto_update() {
    local auto_update_script="$HOME/.access/auto-update.sh"
    
    if [ -f "$auto_update_script" ]; then
        log "Removing auto-update script..."
        rm -f "$auto_update_script"
        log "✓ Auto-update script removed"
    fi
}

# Check for any remaining files
check_remaining() {
    log "Checking for remaining files..."
    
    local remaining=0
    
    # Check common locations
    for location in \
        "$INSTALL_DIR/$SCRIPT_NAME" \
        "$ACCESS_HOME" \
        "/etc/systemd/system/$SERVICE_NAME" \
        "$HOME/.access"
    do
        if [ -e "$location" ]; then
            warn "Found remaining file/directory: $location"
            remaining=$((remaining + 1))
        fi
    done
    
    if [ $remaining -eq 0 ]; then
        log "✓ All Access components removed successfully"
    else
        warn "Some files may remain. Please check manually."
    fi
}

# Parse arguments
FORCE=false
KEEP_CONFIG=false

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=true
            ;;
        --keep-config)
            KEEP_CONFIG=true
            ;;
        --help|-h)
            cat <<EOF
Access Uninstaller

Usage:
    uninstall.sh [options]

Options:
    --force, -f      Skip confirmation prompt
    --keep-config    Keep configuration files
    --help, -h       Show this help

Examples:
    ./uninstall.sh              # Interactive uninstall
    ./uninstall.sh --force      # Uninstall without confirmation
    ./uninstall.sh --keep-config # Keep config files

This will remove:
    - Access binary from $INSTALL_DIR
    - Configuration from ~/.access (unless --keep-config)
    - All cron jobs
    - Systemd service (if exists)
    - Auto-update scripts

EOF
            exit 0
            ;;
    esac
done

# Main uninstall process
main() {
    show_header
    
    # Confirm unless forced
    if [ "$FORCE" = false ]; then
        confirm_uninstall
    fi
    
    log "Starting uninstall process..."
    echo ""
    
    # Stop any running instances
    if pgrep -f "$SCRIPT_NAME" >/dev/null 2>&1; then
        log "Stopping running Access processes..."
        pkill -f "$SCRIPT_NAME" 2>/dev/null || true
    fi
    
    # Remove components
    remove_systemd
    remove_cron
    remove_auto_update
    remove_binary
    
    if [ "$KEEP_CONFIG" = false ]; then
        remove_config
    else
        log "Keeping configuration files as requested"
    fi
    
    echo ""
    check_remaining
    
    echo ""
    echo "=================================================="
    log "Access has been uninstalled"
    
    if [ "$KEEP_CONFIG" = true ]; then
        log "Configuration preserved at: $ACCESS_HOME"
    fi
    
    log "Thank you for using Access!"
    echo "=================================================="
}

# Run main
main