#!/bin/sh
# Update script for Access Eternal
set -e

# update.sh is only ever launched via the access dispatcher (sh "$LIB/update.sh"),
# so dirname "$0" reliably points at the installed $LIB directory where
# init.sh - the single source of truth for these paths - lives. init.sh also
# enforces the root requirement, so no separate check is needed here.
if [ ! -f "$(dirname "$0")/init.sh" ]; then
    printf "ERROR: init.sh not found next to %s. Reinstall Access.\n" "$0" >&2
    exit 1
fi
. "$(dirname "$0")/init.sh"

# Verify LIB directory exists and is a git repository
if [ ! -d "$LIB" ]; then
    printf "ERROR: Access library directory not found at %s\n" "$LIB"
    printf "Please reinstall Access using install.sh\n"
    exit 1
fi

if [ ! -d "$LIB/.git" ]; then
    printf "ERROR: %s is not a git repository\n" "$LIB"
    printf "Please reinstall Access using install.sh\n"
    exit 1
fi

printf "Updating Access Eternal...\n"

# Change to LIB directory and update
cd "$LIB"

# The install is a plain deployment of origin/main, never a place for local
# edits: fetch + hard reset (unlike the old stash+pull) can neither hit merge
# conflicts nor pile up auto-stashes over years of weekly runs. Clear any
# stashes older versions left behind.
git stash clear 2>/dev/null || true
if git fetch origin main && git reset --hard origin/main; then
    printf "Successfully updated source code\n"
else
    printf "ERROR: Failed to update from git repository\n"
    exit 1
fi

# Re-source init.sh from the freshly updated tree so the template rendering
# below runs the newest helper definitions, not the pre-update ones
. "$LIB/init.sh"

# Copy updated access executable to BIN
if [ -f "$LIB/access" ]; then
    cp "$LIB/access" "$BIN"
    chmod +x "$BIN"
    printf "Successfully updated executable at %s\n" "$BIN"
else
    printf "ERROR: access executable not found in %s\n" "$LIB"
    exit 1
fi

# Refresh systemd units and cron jobs from the updated templates, so template
# changes actually reach the running system instead of drifting until the
# next full reinstall. try-restart only touches units that are already active.
if render_systemd_units; then
    printf "Systemd units refreshed\n"
    systemctl try-restart access.service access-sync.timer access-update.timer 2>/dev/null || true
else
    printf "WARNING: Failed to refresh systemd units\n"
fi
if render_cron_jobs; then
    printf "Cron backup jobs refreshed\n"
else
    printf "WARNING: Failed to refresh cron jobs\n"
fi

# Record update timestamp
mkdir -p "$STATE" 2>/dev/null || true
printf "%s\n" "$(date +%s)" > "$STATE/last_upgrade"

printf "Access Eternal updated successfully!\n"