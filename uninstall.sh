#!/bin/sh
# Uninstall script for Access Eternal
set -e

# uninstall.sh is only ever launched via the access dispatcher (sh "$LIB/uninstall.sh"),
# so dirname "$0" reliably points at the installed $LIB directory where
# init.sh - the single source of truth for these paths - lives. init.sh also
# enforces the root requirement, so no separate check is needed here.
if [ ! -f "$(dirname "$0")/init.sh" ]; then
    printf "ERROR: init.sh not found next to %s. Reinstall Access.\n" "$0" >&2
    exit 1
fi
. "$(dirname "$0")/init.sh"

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

# Remove only Access's own cron jobs (match on the marker comment and $BIN,
# not the bare word "access", which could hit unrelated user jobs)
crontab -l 2>/dev/null | grep -v "Access Eternal\|$BIN" | crontab - 2>/dev/null || true

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
if [ -d "$STATE" ]; then
    rm -rf "$STATE"
    printf "Removed state directory: %s\n" "$STATE"
fi

# Remove log directory
if [ -d "$LOG" ]; then
    rm -rf "$LOG"
    printf "Removed log directory: %s\n" "$LOG"
fi

printf "Access Eternal uninstalled successfully!\n"