#!/bin/sh
# Access installation script for Stacker framework

# Check if being installed via Stacker
if [ -z "$STACKER_PKG_NAME" ] && [ -z "$STACKER_INSTALL_MODE" ]; then
    echo "❌ ERROR: @akaoio/access can only be installed via Stacker framework"
    echo ""
    echo "Please install using:"
    echo "  stacker install gh:akaoio/access"
    echo ""
    echo "If you don't have Stacker installed:"
    echo "  curl -sSL https://raw.githubusercontent.com/akaoio/stacker/main/install.sh | sh"
    echo "  stacker install gh:akaoio/access"
    exit 1
fi

echo "Installing @akaoio/access via Stacker..."

# Ensure main executable is accessible
chmod +x access.sh
chmod +x access
chmod +x service.sh
chmod +x health.sh

# Create symlinks for easy access
ln -sf access.sh access 2>/dev/null || true

echo "✅ Access installed successfully"
echo "Available commands:"
echo "  ./access.sh help     # Show help"
echo "  ./access.sh init     # Initialize access"
echo "  ./access.sh status   # Check status"