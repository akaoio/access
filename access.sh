#!/bin/sh
# Access - Eternal Foundation Layer
# Pure POSIX shell implementation - zero dependencies
# "When everything fails, Access survives"

set -e

# Configuration from environment
CONFIG_FILE="${ACCESS_CONFIG:-$HOME/.config/access/config.env}"

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Required variables with defaults
PROVIDER="${PROVIDER:-godaddy}"
DOMAIN="${DOMAIN:-akao.io}"
HOST="${HOST:-peer0}"

# Validate essential config
if [ -z "$GODADDY_KEY" ] || [ -z "$GODADDY_SECRET" ]; then
    echo "ERROR: Missing GODADDY_KEY or GODADDY_SECRET in $CONFIG_FILE"
    exit 1
fi

# Get current IP
get_ip() {
    curl -s ifconfig.me || curl -s ipinfo.io/ip || {
        echo "ERROR: Cannot detect IP"
        exit 1
    }
}

# Update GoDaddy DNS record
update_dns() {
    local ip="$(get_ip)"
    local record_type="A"
    
    # Detect IPv6
    case "$ip" in
        *:*) record_type="AAAA" ;;
    esac
    
    echo "Updating $HOST.$DOMAIN ($record_type) to $ip"
    
    # GoDaddy API call
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        "https://api.godaddy.com/v1/domains/$DOMAIN/records/$record_type/$HOST" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"$ip\", \"ttl\": 600}]")
    
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "✅ DNS updated successfully"
    else
        echo "❌ DNS update failed (HTTP $http_code)"
        exit 1
    fi
}

# Install DHCP hook for true real-time response
install_dhcp_hook() {
    echo "Installing DHCP hook for real-time DNS updates..."
    
    # Create DHCP exit hook
    HOOK_FILE="/etc/dhcp/dhclient-exit-hooks.d/access"
    
    cat << 'EOF' | sudo tee "$HOOK_FILE" > /dev/null
#!/bin/sh
# Access DHCP Hook - True real-time DNS updates
# Triggered instantly when DHCP assigns new IPv6

# Only process IPv6 events
case "$reason" in
    BOUND6|RENEW6|REBOOT6)
        # Log event
        echo "$(date): DHCP IPv6 event ($reason) - new IP: ${new_ip6_address:-unknown}" >> /var/log/access-dhcp.log
        
        # Trigger DNS update
        if [ -x /home/x/.local/bin/access ]; then
            /home/x/.local/bin/access update >> /var/log/access-dhcp.log 2>&1
        fi
        ;;
esac
EOF
    
    sudo chmod +x "$HOOK_FILE"
    echo "✅ DHCP hook installed: $HOOK_FILE"
    echo "DNS updates will now trigger instantly on IPv6 changes"
}

# Main command handling
case "${1:-update}" in
    update) update_dns ;;
    install-hook) install_dhcp_hook ;;
    ip) get_ip ;;
    setup)
        echo "🌟 Access Eternal Setup Wizard"
        echo ""
        
        # Create config directory
        mkdir -p ~/.config/access
        
        # Interactive setup
        echo "📝 Enter your configuration:"
        printf "Domain (default: akao.io): "; read domain
        domain="${domain:-akao.io}"
        
        printf "Host (default: peer0): "; read host  
        host="${host:-peer0}"
        
        printf "GoDaddy API Key: "; read key
        printf "GoDaddy API Secret: "; read secret
        
        # Create config
        cat > ~/.config/access/config.env << EOF
PROVIDER=godaddy
DOMAIN=$domain
HOST=$host
GODADDY_KEY=$key
GODADDY_SECRET=$secret
EOF
        
        chmod 600 ~/.config/access/config.env
        echo "✅ Config created: ~/.config/access/config.env"
        
        # Test configuration
        echo "🧪 Testing DNS update..."
        if access update; then
            echo "✅ Setup complete!"
            echo ""
            echo "🚀 For real-time updates: access install-hook"
        else
            echo "❌ Setup failed - check your API keys"
        fi
        ;;
    
    *) 
        echo "Access - Eternal Foundation Layer"
        echo "Commands: update, setup, install-hook, ip"
        echo ""
        echo "First time? Run: access setup"
        ;;
esac
esac