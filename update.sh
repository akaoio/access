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

# Stash any local changes (shouldn't be any, but just in case)
git stash push -m "Auto-stash before update $(date)" 2>/dev/null || true

# Pull latest changes
if git pull origin main; then
    printf "Successfully updated source code\n"
else
    printf "ERROR: Failed to update from git repository\n"
    exit 1
fi

# Copy updated access executable to BIN
if [ -f "$LIB/access" ]; then
    cp "$LIB/access" "$BIN"
    chmod +x "$BIN"
    printf "Successfully updated executable at %s\n" "$BIN"
else
    printf "ERROR: access executable not found in %s\n" "$LIB"
    exit 1
fi

# Record update timestamp
STATE_DIR="$STATE"
mkdir -p "$STATE_DIR" 2>/dev/null || true
printf "%s\n" "$(date +%s)" > "$STATE_DIR/last_upgrade"

printf "Access Eternal updated successfully!\n"