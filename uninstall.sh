#!/bin/sh
# Access Uninstaller - Uses Manager framework for clean removal
# Removes: binary, configs, services, cron jobs

set -e

# Check if Manager framework is available
check_manager() {
    if [ -d "/usr/local/lib/manager" ]; then
        MANAGER_DIR="/usr/local/lib/manager"
        return 0
    fi
    
    if [ -d "$HOME/manager" ]; then
        MANAGER_DIR="$HOME/manager"
        return 0
    fi
    
    if [ -d "../manager" ]; then
        MANAGER_DIR="../manager"
        return 0
    fi
    
    echo "Warning: Manager framework not found, using basic uninstall"
    return 1
}

# Basic uninstall function if Manager not available
basic_uninstall() {
    echo "[Access] Performing basic uninstall..."
    
    # Remove binary
    if [ -f "/usr/local/bin/access" ]; then
        echo "Removing /usr/local/bin/access..."
        if [ -w "/usr/local/bin" ]; then
            rm -f /usr/local/bin/access
        else
            sudo rm -f /usr/local/bin/access
        fi
    fi
    
    # Remove cron jobs
    echo "Removing cron jobs..."
    crontab -l 2>/dev/null | grep -v "access" | crontab - || true
    
    # Remove systemd service if exists
    if systemctl list-units --full --all | grep -q "access.service"; then
        echo "Removing systemd service..."
        sudo systemctl stop access.service 2>/dev/null || true
        sudo systemctl disable access.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/access.service
        sudo systemctl daemon-reload
    fi
    
    # Remove config directories
    echo "Removing configuration..."
    rm -rf "$HOME/.access" "$HOME/.config/access" "$HOME/.local/share/access"
    
    # Remove clean clone
    if [ -d "$HOME/access" ]; then
        echo "Removing clean clone directory..."
        rm -rf "$HOME/access"
    fi
    
    echo "Access has been uninstalled"
}

# Main uninstall
main() {
    echo "=================================================="
    echo "  Access DNS Synchronization - Uninstaller"
    echo "=================================================="
    echo ""
    
    # Confirm uninstall
    if [ "$1" != "--force" ] && [ "$1" != "-f" ]; then
        printf "This will remove Access completely. Continue? (yes/no): "
        read -r response
        if [ "$response" != "yes" ]; then
            echo "Uninstall cancelled"
            exit 0
        fi
    fi
    
    if check_manager; then
        # Load Manager framework
        . "$MANAGER_DIR/manager.sh"
        
        # Use Manager uninstall functions
        manager_log "Uninstalling Access using Manager framework..."
        
        # Stop service
        manager_service_stop "access" 2>/dev/null || true
        manager_service_uninstall "access" 2>/dev/null || true
        
        # Remove installation
        manager_uninstall "access" || {
            echo "Manager uninstall failed, falling back to basic"
            basic_uninstall
        }
        
        manager_log "Access uninstalled successfully"
    else
        basic_uninstall
    fi
    
    echo ""
    echo "Thank you for using Access!"
}

# Run uninstall
main "$@"