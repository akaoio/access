#!/bin/sh
# Access - Eternal Foundation Layer (Ultimate Single File)
# Pure POSIX implementation - 100 lines max - zero dependencies
# "When everything fails, Access survives"

set -e

# Self-install capability
if [ "$1" = "install" ]; then
    echo "🌟 Installing Access Eternal..."
    mkdir -p ~/.local/bin
    cp "$0" ~/.local/bin/access
    chmod +x ~/.local/bin/access
    echo "✅ Installed to ~/.local/bin/access"
    [ ! -d ~/.config/access ] && echo "Run: access setup"
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

# Runtime detection of actual network service
install_hook() {
    echo "🔍 Runtime network service detection..."
    
    # Test what's actually running and usable
    if systemctl is-active systemd-networkd >/dev/null 2>&1; then
        echo "✅ systemd-networkd detected - using systemd timer instead of hooks"
        
        # Create systemd timer for IP monitoring (better than hooks for systemd-networkd)
        cat << 'TIMER' | sudo tee /etc/systemd/system/access-monitor.timer > /dev/null
[Unit]
Description=Access IP Monitor Timer
[Timer]
OnCalendar=*:0/2
Persistent=true
[Install]
WantedBy=timers.target
TIMER

        cat << 'SERVICE' | sudo tee /etc/systemd/system/access-monitor.service > /dev/null  
[Unit]
Description=Access IP Monitor
[Service]
Type=oneshot
ExecStart=/home/x/.local/bin/access update
SERVICE

        sudo systemctl enable access-monitor.timer
        sudo systemctl start access-monitor.timer
        echo "✅ Real-time monitoring via systemd timer (2min interval)"
        
    elif pgrep dhclient >/dev/null && [ -d /etc/dhcp/dhclient-exit-hooks.d ]; then
        echo "✅ dhclient detected - installing exit hook"
        cat << 'HOOK' | sudo tee /etc/dhcp/dhclient-exit-hooks.d/access > /dev/null
#!/bin/sh
case "$reason" in BOUND6|RENEW6|REBOOT6)
    /home/x/.local/bin/access update >> /var/log/access.log 2>&1
;; esac
HOOK
        sudo chmod +x /etc/dhcp/dhclient-exit-hooks.d/access
        echo "✅ DHCP hook installed"
        
    elif pgrep NetworkManager >/dev/null && [ -d /etc/NetworkManager/dispatcher.d ]; then
        echo "✅ NetworkManager detected - installing dispatcher"
        cat << 'DISPATCHER' | sudo tee /etc/NetworkManager/dispatcher.d/access > /dev/null
#!/bin/sh
case "$2" in up|dhcp6-change) /home/x/.local/bin/access update; esac
DISPATCHER
        sudo chmod +x /etc/NetworkManager/dispatcher.d/access
        echo "✅ NetworkManager dispatcher installed"
        
    else
        echo "❌ No supported network service found"
        echo "💡 Installing cron fallback: */5 * * * * access update"
        (crontab -l 2>/dev/null; echo "*/5 * * * * access update") | crontab -
        echo "✅ Cron fallback installed"
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