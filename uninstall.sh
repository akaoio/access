#!/bin/sh
# Access Uninstaller - Powered by Stacker Framework
# Stacker handles ALL the shit: services, cron, binaries, configs, everything

set -e

# Find and load Stacker - it's strong enough to handle this
if [ -f "$HOME/manager/manager.sh" ]; then
    . "$HOME/manager/manager.sh"
elif [ -f "/usr/local/lib/manager/manager.sh" ]; then
    . "/usr/local/lib/manager/manager.sh"
else
    echo "ERROR: Stacker framework not found!"
    echo "Stacker is required for proper uninstallation."
    echo ""
    echo "Install Stacker first:"
    echo "  git clone https://github.com/akaoio/manager.git ~/manager"
    echo ""
    echo "Stacker handles all aspects of uninstallation properly."
    exit 1
fi

# Confirm uninstallation
if [ "$1" != "--force" ] && [ "$1" != "-f" ]; then
    echo "=================================================="
    echo "  Access DNS Synchronization - Uninstaller"
    echo "=================================================="
    echo ""
    echo "This will remove Access completely:"
    echo "  • Binary files and scripts"
    echo "  • Systemd services (if installed)"
    echo "  • Cron jobs (if installed)"
    echo "  • Configuration files (including API keys!)"
    echo "  • Log files and data"
    echo ""
    printf "Continue with uninstallation? (yes/no): "
    read -r response
    if [ "$response" != "yes" ]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
fi

# Initialize Stacker for Access
stacker_init "access" \
             "https://github.com/akaoio/access.git" \
             "access.sh" \
             "Dynamic DNS IP Synchronization"

# Let Stacker handle ALL the shit - it's strong enough!
stacker_log "Stacker will now handle complete removal of Access..."

# Parse options
UNINSTALL_OPTS=""
for arg in "$@"; do
    case "$arg" in
        --keep-config)
            UNINSTALL_OPTS="$UNINSTALL_OPTS --keep-config"
            stacker_log "Keeping configuration files (API keys preserved)"
            ;;
        --keep-data)
            UNINSTALL_OPTS="$UNINSTALL_OPTS --keep-data"
            stacker_log "Keeping data and log files"
            ;;
    esac
done

# Stacker handles everything:
# - Stops and removes systemd services (system AND user)
# - Removes cron jobs
# - Deletes binaries from all locations
# - Cleans up config directories (unless --keep-config)
# - Removes data and logs (unless --keep-data)
# - Handles both root and non-root installations
# - Cleans up symlinks
# - Updates the Stacker registry

stacker_uninstall $UNINSTALL_OPTS || {
    stacker_error "Uninstallation failed!"
    exit 1
}

echo ""
echo "=================================================="
echo "  Access has been completely uninstalled"
echo "=================================================="
echo ""
echo "Thank you for using Access!"
echo ""

# Final note about Stacker
if [ -z "$UNINSTALL_OPTS" ]; then
    echo "Note: All Access files have been removed."
    echo "Stacker framework remains installed for other tools."
fi