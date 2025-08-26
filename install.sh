#!/bin/sh
# Access installer - Pure shell installation

set -e

INSTALL_DIR="/usr/local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/akaoio/access/main/access.sh"
SCRIPT_NAME="access"

echo "Installing Access - Pure shell network access layer"
echo "================================================"

# Check for required tools
check_requirements() {
    local missing=""
    
    # Check for curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing="$missing curl/wget"
    fi
    
    # Check for basic DNS tools
    if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
        echo "Warning: No DNS tools found (dig/nslookup). HTTP detection will be used."
    fi
    
    if [ -n "$missing" ]; then
        echo "Error: Required tools missing:$missing"
        echo "Please install them and try again."
        exit 1
    fi
}

# Download script
download_script() {
    local temp_file="/tmp/access_install_$$"
    
    echo "Downloading Access..."
    if command -v curl >/dev/null 2>&1; then
        curl -sSL "$SCRIPT_URL" -o "$temp_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$SCRIPT_URL" -O "$temp_file"
    fi
    
    if [ ! -f "$temp_file" ]; then
        echo "Error: Failed to download Access"
        exit 1
    fi
    
    echo "$temp_file"
}

# Install script
install_script() {
    local src="$1"
    local dest="$INSTALL_DIR/$SCRIPT_NAME"
    
    # Check if we need sudo
    if [ -w "$INSTALL_DIR" ]; then
        cp "$src" "$dest"
        chmod +x "$dest"
    else
        echo "Installing to $INSTALL_DIR (requires sudo)..."
        sudo cp "$src" "$dest"
        sudo chmod +x "$dest"
    fi
    
    # Create config directory
    mkdir -p "$HOME/.access"
    
    echo "✓ Access installed to $dest"
}

# Setup systemd service (optional)
setup_service() {
    if [ "$1" = "--service" ] && command -v systemctl >/dev/null 2>&1; then
        echo "Setting up systemd service..."
        
        cat <<EOF | sudo tee /etc/systemd/system/access.service >/dev/null
[Unit]
Description=Access - Network access layer
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$INSTALL_DIR/$SCRIPT_NAME daemon
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        echo "✓ Systemd service created"
        echo "  Start with: sudo systemctl start access"
        echo "  Enable on boot: sudo systemctl enable access"
    fi
}

# Setup cron job (alternative to systemd)
setup_cron() {
    if [ "$1" = "--cron" ]; then
        echo "Setting up cron job..."
        
        # Add to user's crontab
        (crontab -l 2>/dev/null | grep -v "access update"; echo "*/5 * * * * $INSTALL_DIR/$SCRIPT_NAME update") | crontab -
        
        echo "✓ Cron job created (runs every 5 minutes)"
    fi
}

# Main installation
main() {
    check_requirements
    
    # Download
    temp_file=$(download_script)
    
    # Install
    install_script "$temp_file"
    
    # Cleanup
    rm -f "$temp_file"
    
    # Optional service setup
    setup_service "$1"
    setup_cron "$1"
    
    echo ""
    echo "Installation complete!"
    echo "====================="
    echo ""
    echo "Quick start:"
    echo "  1. Configure provider:"
    echo "     access config godaddy --key=YOUR_KEY --secret=YOUR_SECRET --domain=example.com"
    echo ""
    echo "  2. Test IP detection:"
    echo "     access ip"
    echo ""
    echo "  3. Update DNS:"
    echo "     access update"
    echo ""
    echo "  4. Run as daemon:"
    echo "     access daemon"
    echo ""
    echo "For help: access help"
}

main "$@"