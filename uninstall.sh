#!/bin/sh
# Access Uninstaller - Powered by Manager Framework
# Manager handles ALL the shit: services, cron, binaries, configs, everything

set -e

# Find and load Manager - it's strong enough to handle this
if [ -f "$HOME/manager/manager.sh" ]; then
    . "$HOME/manager/manager.sh"
elif [ -f "/usr/local/lib/manager/manager.sh" ]; then
    . "/usr/local/lib/manager/manager.sh"
elif [ -f "../manager/manager.sh" ]; then
    . "../manager/manager.sh"
else
    echo "ERROR: Manager framework not found!"
    echo "Manager is required for proper uninstallation."
    echo "Install Manager first: git clone https://github.com/akaoio/manager.git ~/manager"
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

# Initialize Manager for Access
manager_init "access" \
             "https://github.com/akaoio/access.git" \
             "access.sh" \
             "Dynamic DNS IP Synchronization"

# Let Manager handle ALL the shit - it's strong enough!
manager_log "Manager will now handle complete removal of Access..."

# Parse options
UNINSTALL_OPTS=""
for arg in "$@"; do
    case "$arg" in
        --keep-config)
            UNINSTALL_OPTS="$UNINSTALL_OPTS --keep-config"
            manager_log "Keeping configuration files (API keys preserved)"
            ;;
        --keep-data)
            UNINSTALL_OPTS="$UNINSTALL_OPTS --keep-data"
            manager_log "Keeping data and log files"
            ;;
    esac
done

# Manager handles everything:
# - Stops and removes systemd services (system AND user)
# - Removes cron jobs
# - Deletes binaries from all locations
# - Cleans up config directories (unless --keep-config)
# - Removes data and logs (unless --keep-data)
# - Handles both root and non-root installations
# - Cleans up symlinks
# - Updates the Manager registry

manager_uninstall $UNINSTALL_OPTS || {
    manager_error "Uninstallation failed!"
    exit 1
}

echo ""
echo "=================================================="
echo "  Access has been completely uninstalled"
echo "=================================================="
echo ""
echo "Thank you for using Access!"
echo ""

# Final note about Manager
if [ -z "$UNINSTALL_OPTS" ]; then
    echo "Note: All Access files have been removed."
    echo "Manager framework remains installed for other tools."
fi