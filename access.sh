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

# Helper functions
ensure_directories() {
    mkdir -p "$XDG_CONFIG_HOME/access" \
             "$XDG_STATE_HOME/access" \
             "$XDG_CONFIG_HOME/systemd/user" \
             "$XDG_BIN_HOME"
}

install_binary() {
    _install_source="$1"
    cp "$_install_source" "$ACCESS_BIN" && chmod +x "$ACCESS_BIN"
}

# Get IP using iproute2 (no external dependencies)
get_ip() {
    ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1 ||
    ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1
}

# Update DNS 
update_dns() {
    [ -z "$GODADDY_KEY" ] && { echo "⚠️  No config found. Run: access setup"; return 1; }
    
    ip=$(get_ip)
    [ -z "$ip" ] && { echo "⚠️  No IP address found"; return 1; }
    
    # Check if IP changed to avoid unnecessary updates
    LAST_IP_FILE="$XDG_STATE_HOME/access/last_ip"
    ensure_directories
    
    if [ -f "$LAST_IP_FILE" ] && [ "$(cat "$LAST_IP_FILE" 2>/dev/null)" = "$ip" ]; then
        echo "🔄 IP unchanged ($ip) - skipping DNS update"
        return 0
    fi
    
    # Store default values once
    _dns_host="${HOST:-$DEFAULT_HOST}"
    _dns_domain="${DOMAIN:-$DEFAULT_DOMAIN}"
    _dns_type="A"; case "$ip" in *:*) _dns_type="AAAA";; esac
    
    echo "Updating $_dns_host.$_dns_domain ($_dns_type) to $ip"
    
    if curl -s -X PUT "https://api.godaddy.com/v1/domains/$_dns_domain/records/$_dns_type/$_dns_host" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"$ip\",\"ttl\":600}]" >/dev/null; then
        echo "✅ DNS updated"
        echo "$ip" > "$LAST_IP_FILE"
    else
        echo "❌ DNS update failed - will retry on next IP change"
        return 1
    fi
}

# Private functions - not exposed in public API
create_config() {
    echo "🌟 Setup"
    ensure_directories
    
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

start_monitor_daemon() {
    echo "🔥 Starting real-time IP monitor..."
    echo "$(date): Starting IP monitor session" >&2
    
    # Direct IP monitoring - systemd handles restarts
    exec ip monitor addr 2>/dev/null | while read line; do
        case "$line" in
            *"scope global"*)
                echo "$(date): IP change detected - $line" >&2
                update_dns || echo "$(date): DNS update failed, will retry on next change" >&2
                ;;
        esac
    done
}

create_service() {
    if systemctl --user daemon-reload 2>/dev/null; then
        ensure_directories
        cat > "$XDG_CONFIG_HOME/systemd/user/access.service" << EOF
[Unit]
Description=Access IP Monitor

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=$ACCESS_BIN _monitor
StandardOutput=append:$XDG_STATE_HOME/access/access.log
StandardError=append:$XDG_STATE_HOME/access/error.log

[Install]
WantedBy=default.target
EOF
        systemctl --user enable --now access.service
        echo "✅ Monitor service installed (real-time)"
    else
        (crontab -l 2>/dev/null; echo "*/5 * * * * $ACCESS_BIN update") | crontab -
        echo "✅ Cron installed (5min)"
    fi
    
    # Install auto-upgrade cron (weekly) + backup monitoring (every 15 min)
    (crontab -l 2>/dev/null | grep -v "$ACCESS_BIN"; echo "0 3 * * 0 $ACCESS_BIN upgrade"; echo "*/15 * * * * $ACCESS_BIN update") | crontab -
    echo "✅ Auto-upgrade installed (weekly)"
    echo "✅ Backup monitoring installed (15min)"
}

# Public API - clean and simple
do_install() {
    echo "🌟 Installing Access..."
    ensure_directories
    
    # Only install if not already in correct location or if different
    if [ "$0" != "$ACCESS_BIN" ]; then
        install_binary "$0"
    fi
    echo "✅ Installed and configured"
    
    # Auto-setup if no config
    [ ! -f "$CONFIG_FILE" ] && create_config
    
    # Create and start service
    create_service
}

do_upgrade() {
    curl -s https://raw.githubusercontent.com/akaoio/access/main/access.sh > /tmp/access-new
    if [ -s /tmp/access-new ] && head -1 /tmp/access-new | grep -q "#!/bin/sh"; then
        install_binary /tmp/access-new
        echo "✅ Upgraded binary"
        
        # Auto-restart service if running
        if systemctl --user is-active access.service >/dev/null 2>&1; then
            systemctl --user restart access.service
            echo "✅ Service restarted with new version"
        fi
        
        echo "✅ Upgrade complete"
    fi
    rm -f /tmp/access-new
}

do_uninstall() {
    systemctl --user stop access.service 2>/dev/null || true
    rm -f "$ACCESS_BIN" "$XDG_CONFIG_HOME/systemd/user/access.service"
    crontab -l 2>/dev/null | grep -v "$ACCESS_BIN" | crontab - 2>/dev/null || true
    echo "✅ Uninstalled"
}

# Commands - Pure Public API
case "${1:-install}" in
    install) do_install ;;
    update) update_dns ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    _monitor) start_monitor_daemon ;;  # Internal only
    *) echo "Access: install|update|upgrade|uninstall" ;;
esac