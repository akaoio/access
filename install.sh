#!/bin/sh
# Access installation script for Stacker framework

echo "Installing @akaoio/access..."

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