#!/bin/sh
# Access - Stacker Enable Script
# Enables Access package and integrates with system PATH

set -e

PACKAGE_DIR="$(pwd)"
echo "Enabling Access DNS synchronization..."

# Add access command to PATH by creating symlink
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

# Create symlink to access.sh in user's bin directory
ACCESS_SCRIPT="$PACKAGE_DIR/access.sh"
ACCESS_BIN="$BIN_DIR/access"

if [ -f "$ACCESS_SCRIPT" ]; then
    # Remove existing symlink if present
    [ -L "$ACCESS_BIN" ] && rm -f "$ACCESS_BIN"
    
    # Create new symlink
    ln -s "$ACCESS_SCRIPT" "$ACCESS_BIN"
    echo "✓ Created command: access -> $ACCESS_SCRIPT"
else
    echo "! Warning: access.sh not found at $ACCESS_SCRIPT"
fi

# Verify PATH includes ~/.local/bin
if echo "$PATH" | grep -q "$BIN_DIR"; then
    echo "✓ $BIN_DIR is in PATH"
else
    echo "! Warning: $BIN_DIR is not in PATH"
    echo "  Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Test access command
if command -v access >/dev/null 2>&1; then
    echo "✓ 'access' command is now available"
    echo ""
    echo "Try running:"
    echo "  access --help"
    echo "  access status"
    echo "  access health"
else
    echo "! 'access' command not found in PATH"
    echo "  You may need to restart your shell or run:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "✅ Access DNS synchronization enabled successfully!"