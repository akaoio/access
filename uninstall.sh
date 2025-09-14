#!/bin/sh
# Uninstall script for Access Eternal
set -e

# Get paths from init.sh if available
if [ -f "$(dirname "$0")/init.sh" ]; then
    . "$(dirname "$0")/init.sh"
elif [ -f "/usr/local/lib/access/init.sh" ]; then
    . "/usr/local/lib/access/init.sh"
else
    # Fallback defaults
    BIN="/usr/local/bin/access"
    LIB="/usr/local/lib/access"
    CONFIG="/etc/access/config.env"
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    printf "This script must be run as root. Please use sudo.\n"
    exit 1
fi

printf "Uninstalling Access Eternal...\n"

# Stop any running systemd services
systemctl stop access.service 2>/dev/null || true
systemctl stop access-sync.timer 2>/dev/null || true
systemctl stop access-update.timer 2>/dev/null || true
systemctl disable access.service 2>/dev/null || true
systemctl disable access-sync.timer 2>/dev/null || true  
systemctl disable access-update.timer 2>/dev/null || true

# Remove systemd service files
rm -f /etc/systemd/system/access.service
rm -f /etc/systemd/system/access-sync.service
rm -f /etc/systemd/system/access-sync.timer
rm -f /etc/systemd/system/access-update.service
rm -f /etc/systemd/system/access-update.timer

# Reload systemd
systemctl daemon-reload 2>/dev/null || true

# Remove cron jobs
crontab -l 2>/dev/null | grep -v access | crontab - 2>/dev/null || true

# Remove executable
if [ -f "$BIN" ]; then
    rm -f "$BIN"
    printf "Removed executable: %s\n" "$BIN"
else
    printf "Executable not found: %s\n" "$BIN"
fi

# Remove library directory
if [ -d "$LIB" ]; then
    rm -rf "$LIB"
    printf "Removed library directory: %s\n" "$LIB"
else
    printf "Library directory not found: %s\n" "$LIB"
fi

# Remove configuration directory (ask for confirmation)
if [ -f "$CONFIG" ]; then
    printf "Remove configuration file %s? [y/N]: " "$CONFIG"
    read -r confirm < /dev/tty
    case "$confirm" in
        [Yy]*)
            rm -rf "$(dirname "$CONFIG")"
            printf "Removed configuration directory: %s\n" "$(dirname "$CONFIG")"
            ;;
        *)
            printf "Configuration preserved at: %s\n" "$CONFIG"
            ;;
    esac
fi

# Remove state directory
STATE_DIR="/var/lib/access"
if [ -d "$STATE_DIR" ]; then
    rm -rf "$STATE_DIR"
    printf "Removed state directory: %s\n" "$STATE_DIR"
fi

printf "Access Eternal uninstalled successfully!\n"