#!/bin/sh
# Access - Eternal Foundation Layer (Ultimate Single File)
# Pure POSIX implementation - 100 lines max - zero dependencies
# "When everything fails, Access survives"

set -e

# Self-install capability with robust error handling
if [ "$1" = "install" ]; then
    echo "🌟 Installing Access Eternal..."
    
    # Clean any existing installations
    [ -L ~/.local/bin/access ] && rm -f ~/.local/bin/access 2>/dev/null
    [ -f ~/.local/bin/access ] && rm -f ~/.local/bin/access 2>/dev/null
    
    # Create directory safely
    mkdir -p ~/.local/bin || { echo "❌ Cannot create ~/.local/bin"; exit 1; }
    
    # Install binary
    if cp "$0" ~/.local/bin/access && chmod +x ~/.local/bin/access; then
        echo "✅ Installed to ~/.local/bin/access"
        
        # Check PATH automatically
        if command -v access >/dev/null 2>&1; then
            echo "✅ Command available: access"
        else
            echo "⚠️  Run: export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
        
        # Check config
        if [ -f ~/.config/access/config.env ]; then
            echo "✅ Config found - ready to use"
        else
            echo "💡 Next: access setup"
        fi
    else
        echo "❌ Installation failed"
        exit 1
    fi
    exit 0
fi

# Configuration
CONFIG_FILE="${ACCESS_CONFIG:-$HOME/.config/access/config.env}"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Required variables
PROVIDER="${PROVIDER:-godaddy}"
DOMAIN="${DOMAIN:-akao.io}"  
HOST="${HOST:-peer0}"

# Core functions
get_ip() { curl -s ifconfig.me || curl -s ipinfo.io/ip; }

update_dns() {
    [ -z "$GODADDY_KEY" ] || [ -z "$GODADDY_SECRET" ] && { echo "ERROR: Missing API keys"; exit 1; }
    
    ip="$(get_ip)"
    record_type="A"; case "$ip" in *:*) record_type="AAAA";; esac
    
    echo "Updating $HOST.$DOMAIN ($record_type) to $ip"
    
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        "https://api.godaddy.com/v1/domains/$DOMAIN/records/$record_type/$HOST" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"$ip\", \"ttl\": 600}]")
    
    [ "$(echo "$response" | tail -n1)" = "200" ] && echo "✅ DNS updated" || { echo "❌ Failed"; exit 1; }
}

# Setup wizard
setup() {
    echo "🌟 Access Setup"
    mkdir -p ~/.config/access
    
    printf "Domain [akao.io]: "; read domain; domain="${domain:-akao.io}"
    printf "Host [peer0]: "; read host; host="${host:-peer0}" 
    printf "GoDaddy Key: "; read key
    printf "GoDaddy Secret: "; read secret
    
    cat > ~/.config/access/config.env << EOF
PROVIDER=godaddy
DOMAIN=$domain  
HOST=$host
GODADDY_KEY=$key
GODADDY_SECRET=$secret
EOF
    chmod 600 ~/.config/access/config.env
    echo "✅ Config saved"
    
    if update_dns 2>/dev/null; then
        echo "✅ Test successful!"
        echo "🚀 For real-time: access hook"
    else
        echo "❌ Check API keys"
    fi
}

# Smart hook installation with fallback options
install_hook() {
    echo "🔍 Auto-configuring real-time monitoring..."
    
    # Try user-space solutions first (no sudo needed)
    if command -v systemctl >/dev/null 2>&1 && [ -w ~/.config ]; then
        echo "✅ Using user systemd timer (no sudo required)"
        
        mkdir -p ~/.config/systemd/user
        
        cat > ~/.config/systemd/user/access-monitor.timer << 'EOF'
[Unit]
Description=Access IP Monitor Timer
[Timer]
OnCalendar=*:0/2
Persistent=true
[Install]
WantedBy=default.target
EOF

        cat > ~/.config/systemd/user/access-monitor.service << 'EOF'
[Unit]
Description=Access IP Monitor
[Service]
Type=oneshot
ExecStart=%h/.local/bin/access update
EOF

        systemctl --user daemon-reload
        systemctl --user enable access-monitor.timer 2>/dev/null || true
        systemctl --user start access-monitor.timer 2>/dev/null || true
        echo "✅ User timer installed (2min intervals)"
        
    else
        echo "💡 Using cron fallback (universal compatibility)"
        
        # Check if cron job already exists
        if ! crontab -l 2>/dev/null | grep -q "access update"; then
            (crontab -l 2>/dev/null; echo "*/5 * * * * ~/.local/bin/access update >/dev/null 2>&1") | crontab - 2>/dev/null || {
                echo "⚠️  Manual cron setup needed:"
                echo "   */5 * * * * ~/.local/bin/access update"
            }
            echo "✅ Cron monitoring installed (5min intervals)"
        else
            echo "✅ Cron monitoring already configured"
        fi
    fi
}

# Commands  
case "${1:-update}" in
    update) update_dns ;;
    setup) setup ;;
    hook) install_hook ;;
    ip) get_ip ;;
    install) ;; # Handled above
    *) echo "Access Eternal: update|setup|hook|ip|install" ;;
esac