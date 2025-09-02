#!/bin/sh
# Access Eternal - Minimal POSIX dynamic DNS
# "When everything fails, Access survives"

set -e

# XDG Base Directory Specification
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
ACCESS_BIN="$XDG_BIN_HOME/access"

# Defaults
DEFAULT_DOMAIN="akao.io"
DEFAULT_HOST="peer0"

# Load config
CONFIG_FILE="$XDG_CONFIG_HOME/access/config.env"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Get IP using iproute2 (no external dependencies)
get_ip() {
    ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1 ||
    ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1
}

# Update DNS 
update_dns() {
    [ -z "$GODADDY_KEY" ] && { echo "⚠️  No config found. Run: access setup"; return 1; }
    
    ip=$(get_ip)
    type="A"; case "$ip" in *:*) type="AAAA";; esac
    
    echo "Updating ${HOST:-$DEFAULT_HOST}.${DOMAIN:-$DEFAULT_DOMAIN} ($type) to $ip"
    
    curl -s -X PUT "https://api.godaddy.com/v1/domains/${DOMAIN:-$DEFAULT_DOMAIN}/records/$type/${HOST:-$DEFAULT_HOST}" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"$ip\",\"ttl\":600}]" >/dev/null &&
    echo "✅ DNS updated" || { echo "❌ Failed"; exit 1; }
}

# Setup
setup() {
    echo "🌟 Setup"
    mkdir -p "$XDG_CONFIG_HOME/access"
    
    printf "Domain [$DEFAULT_DOMAIN]: "; read domain; domain=${domain:-$DEFAULT_DOMAIN}
    printf "Host [$DEFAULT_HOST]: "; read host; host=${host:-$DEFAULT_HOST}
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

# Real-time monitor with systemd service support
monitor() {
    echo "🔥 Starting resilient real-time monitor..."
    
    # Daemon mode (for systemd service)
    if [ "$2" = "daemon" ]; then
        # Resilient monitoring loop
        while true; do
            echo "$(date): Starting IP monitor session" >&2
            
            # Monitor with restart on failure
            ip monitor addr 2>/dev/null | while read line; do
                case "$line" in
                    *"scope global"*)
                        echo "$(date): IP change detected - $line" >&2
                        update_dns
                        ;;
                esac
            done
            
            echo "$(date): Monitor session ended - restarting in 5s" >&2
            sleep 5
        done
    else
        echo "Use systemd service: systemctl --user start access.service"
    fi
}

# Auto-upgrade
upgrade() {
    curl -s https://raw.githubusercontent.com/akaoio/access/main/access.sh > /tmp/access-new
    if [ -s /tmp/access-new ] && head -1 /tmp/access-new | grep -q "#!/bin/sh"; then
        cp /tmp/access-new "$ACCESS_BIN" && chmod +x "$ACCESS_BIN"
        echo "✅ Upgraded"
    fi
    rm -f /tmp/access-new
}

# Install monitoring (choose best option)
hook() {
    if systemctl --user daemon-reload 2>/dev/null; then
        mkdir -p "$XDG_CONFIG_HOME/systemd/user"
        cat > "$XDG_CONFIG_HOME/systemd/user/access.service" << EOF
[Unit]
Description=Access IP Monitor

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=$ACCESS_BIN monitor daemon
StandardOutput=append:$XDG_STATE_HOME/access/access.log
StandardError=append:$XDG_STATE_HOME/access/access.log

[Install]
WantedBy=default.target
EOF
        mkdir -p "$XDG_STATE_HOME/access"
        systemctl --user enable --now access.service
        echo "✅ Monitor service installed (real-time)"
    else
        (crontab -l 2>/dev/null; echo "*/5 * * * * $ACCESS_BIN update") | crontab -
        echo "✅ Cron installed (5min)"
    fi
}

# Uninstall
uninstall() {
    systemctl --user stop access.service 2>/dev/null || true
    rm -f "$ACCESS_BIN" "$XDG_CONFIG_HOME/systemd/user/access.service"
    crontab -l 2>/dev/null | grep -v access | crontab - 2>/dev/null || true
    echo "✅ Uninstalled"
}

# Commands
case "${1:-install}" in
    install)
        echo "🌟 Installing Access..."
        [ -f "$ACCESS_BIN" ] && rm "$ACCESS_BIN"
        mkdir -p "$XDG_BIN_HOME"
        cp "$0" "$ACCESS_BIN" && chmod +x "$ACCESS_BIN"
        echo "✅ Installed and configured"
        
        # Auto-setup if no config
        if [ ! -f "$CONFIG_FILE" ]; then
            "$ACCESS_BIN" setup
        fi
        
        # Auto-hook
        "$ACCESS_BIN" hook
        ;;
    update) update_dns ;;
    upgrade) upgrade ;;
    uninstall) uninstall ;;
    *) echo "Access: install|update|upgrade|uninstall" ;;
esac