#!/bin/sh
# Access Eternal - One-line installer
# Usage: curl -sSL https://github.com/akaoio/access/raw/main/install.sh | sh

set -e

echo "🌟 Installing Access Eternal Foundation Layer..."

# Download access.sh
echo "📥 Downloading access.sh..."
curl -sSL https://github.com/akaoio/access/raw/main/access.sh -o access.sh
chmod +x access.sh

# Install to PATH
mkdir -p ~/.local/bin
mv access.sh ~/.local/bin/access
echo "✅ Installed to ~/.local/bin/access"

# Check PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "⚠️  Add to your shell profile:"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "🎯 Next steps:"
echo "1. Get GoDaddy API keys from: https://developer.godaddy.com/"
echo "2. Run: access setup"
echo ""
echo "✨ Access Eternal installed successfully!"