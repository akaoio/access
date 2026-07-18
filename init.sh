#!/bin/sh
set -e # Exit immediately if a command exits with a non-zero status

# Read-only commands (access ip/help) set ACCESS_SKIP_ROOT_CHECK=1 before
# sourcing this file; everything else must run as root.
if [ -z "$ACCESS_SKIP_ROOT_CHECK" ] && [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Environment - single source of truth for all paths. Overridable via env
# for tests and development; defaults are the installed FHS locations.
CONFIG="${CONFIG:-/etc/access/config.env}"
BIN="${BIN:-/usr/local/bin/access}"
LIB="${LIB:-/usr/local/lib/access}"
STATE="${STATE:-/var/lib/access}"
LOG="${LOG:-/var/log/access}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
INSTALLED=false

# Load config if readable (-r, not -f: the file is chmod 600, so non-root
# ip/help must skip it instead of dying on an unreadable source)
if [ -r "$CONFIG" ]; then
    . "$CONFIG"
fi

# Configs created before multi-provider support have no PROVIDER field
PROVIDER="${PROVIDER:-godaddy}"

# Check if Access is already installed
if [ -f "$BIN" ] && [ -d "$LIB" ]; then
    INSTALLED=true
fi

# Render systemd unit templates from $LIB into $SYSTEMD_DIR and reload.
# Shared by install.sh and update.sh so updated templates can never drift
# from what a fresh install would lay down.
render_systemd_units() {
    for _unit in access.service access-sync.service access-sync.timer access-update.service access-update.timer; do
        sed "s|__BIN__|$BIN|g; s|__LIB__|$LIB|g; s|__LOG__|$LOG|g" \
            "$LIB/$_unit.template" > "$SYSTEMD_DIR/$_unit" || return 1
    done
    systemctl daemon-reload
}

# Install/refresh the cron backup jobs from crontab.template, replacing any
# previous Access entries. Shared by install.sh and update.sh.
render_cron_jobs() {
    _temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v "Access Eternal\|$BIN" > "$_temp_cron" || true
    sed "s|__BIN__|$BIN|g; s|__LOG__|$LOG|g" "$LIB/crontab.template" >> "$_temp_cron" || { rm -f "$_temp_cron"; return 1; }
    crontab "$_temp_cron" || { rm -f "$_temp_cron"; return 1; }
    rm -f "$_temp_cron"
}
