#!/bin/sh
# Access Eternal - Minimal 100-line version
# "When everything fails, Access survives"

set -e

# Self-install
if [ "$1" = "install" ]; then
    echo "🌟 Installing Access..."
    [ -f ~/.local/bin/access ] && rm ~/.local/bin/access
    mkdir -p ~/.local/bin
    cp "$0" ~/.local/bin/access && chmod +x ~/.local/bin/access
    echo "✅ Installed. Run: access setup"
    exit 0
fi

# Load config
CONFIG_FILE="$HOME/.config/access/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Get IP using iproute2 (no external dependencies)
get_ip() {
    ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1 ||
    ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1
}

# Update DNS 
update_dns() {
    [ -z "$GODADDY_KEY" ] && { echo "ERROR: No API key"; exit 1; }
    
    ip=$(get_ip)
    type="A"; case "$ip" in *:*) type="AAAA";; esac
    
    echo "Updating ${HOST:-peer0}.${DOMAIN:-akao.io} ($type) to $ip"
    
    curl -s -X PUT "https://api.godaddy.com/v1/domains/${DOMAIN:-akao.io}/records/$type/${HOST:-peer0}" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"$ip\",\"ttl\":600}]" >/dev/null &&
    echo "✅ DNS updated" || { echo "❌ Failed"; exit 1; }
}

# Setup
setup() {
    echo "🌟 Setup"
    mkdir -p ~/.config/access
    
    printf "Domain [akao.io]: "; read domain; domain=${domain:-akao.io}
    printf "Host [peer0]: "; read host; host=${host:-peer0}
    printf "GoDaddy Key: "; read key
    printf "Secret: "; read secret
    
    cat > "$CONFIG_FILE" << EOF
DOMAIN=$domain
HOST=$host
GODADDY_KEY=$key
GODADDY_SECRET=$secret
EOF
    chmod 600 "$CONFIG_FILE"
    echo "✅ Config saved"
    update_dns && echo "✅ Test OK"
}

# Real-time monitor  
monitor() {
    echo "🔥 Real-time monitoring..."
    ip monitor addr | while read line; do
        case "$line" in *"scope global"*) echo "IP changed"; update_dns;; esac
    done
}

# Auto-upgrade
upgrade() {
    curl -s https://github.com/akaoio/access/raw/main/access.sh > /tmp/access-new
    if [ -s /tmp/access-new ] && head -1 /tmp/access-new | grep -q "#!/bin/sh"; then
        cp /tmp/access-new ~/.local/bin/access && chmod +x ~/.local/bin/access
        echo "✅ Upgraded"
    fi
    rm -f /tmp/access-new
}

# Install monitoring (choose best option)
hook() {
    if systemctl --user start 2>/dev/null; then
        mkdir -p ~/.config/systemd/user
        cat > ~/.config/systemd/user/access.timer << 'EOF'
[Timer]
OnCalendar=*:0/5
[Install]
WantedBy=default.target
EOF
        cat > ~/.config/systemd/user/access.service << 'EOF'
[Service]
Type=oneshot  
ExecStart=/bin/sh -c '. ~/.local/bin/access; update_dns'
EOF
        systemctl --user enable access.timer && systemctl --user start access.timer
        echo "✅ Timer installed (5min)"
    else
        (crontab -l 2>/dev/null; echo "*/5 * * * * ~/.local/bin/access update") | crontab -
        echo "✅ Cron installed (5min)"
    fi
}

# Uninstall
uninstall() {
    systemctl --user stop access.timer 2>/dev/null || true
    rm -f ~/.local/bin/access ~/.config/systemd/user/access.*
    crontab -l 2>/dev/null | grep -v access | crontab - 2>/dev/null || true
    echo "✅ Uninstalled"
}

# Commands
case "${1:-update}" in
    update) update_dns ;;
    monitor) monitor ;;
    setup) setup ;;
    hook) hook ;;
    upgrade) upgrade ;;
    uninstall) uninstall ;;
    ip) get_ip ;;
    install) ;;
    *) echo "Access: update|monitor|setup|hook|upgrade|uninstall|ip|install" ;;
esac