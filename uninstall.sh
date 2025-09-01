#!/bin/sh
# Access uninstallation script for Stacker framework

echo "Uninstalling @akaoio/access..."

# Stop any running services
if [ -f "./service.sh" ]; then
    ./service.sh stop 2>/dev/null || true
fi

# Remove configuration (optional - user data)
# rm -rf ~/.config/access 2>/dev/null || true

echo "✅ Access uninstalled successfully"
echo "Configuration preserved in ~/.config/access"