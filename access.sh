#!/bin/sh
# Access Eternal - Minimal POSIX dynamic DNS
set -e

# Environment
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
[ -w "/usr/local/bin" ] 2>/dev/null && XDG_BIN_HOME="/usr/local/bin"
ACCESS_BIN="$XDG_BIN_HOME/access"
CONFIG_FILE="$XDG_CONFIG_HOME/access/config.env"

_hostname=$(hostname 2>/dev/null || echo "peer0.akao.io")
DEFAULT_HOST="${_hostname%%.*}"
DEFAULT_DOMAIN="${_hostname#*.}"
[ "$DEFAULT_DOMAIN" = "$DEFAULT_HOST" ] && DEFAULT_DOMAIN="akao.io"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

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
        (crontab -l 2>/dev/null; echo "*/5 * * * * $ACCESS_BIN sync") | crontab -
        echo "✅ Cron installed (5min)"
    fi
    
    # Install auto-upgrade cron (weekly) + backup monitoring (every 5 min)
    (crontab -l 2>/dev/null | grep -v "$ACCESS_BIN"; echo "0 3 * * 0 $ACCESS_BIN upgrade"; echo "*/5 * * * * $ACCESS_BIN sync") | crontab -
    echo "✅ Auto-upgrade installed (weekly)"
    echo "✅ Backup monitoring installed (5min)"
}

get_ip() {
    ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1 ||
    ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1
}

update_dns() {
    [ -z "$GODADDY_KEY" ] && { echo "⚠️  No config. Run: access setup"; return 1; }
    ip=$(get_ip)
    [ -z "$ip" ] && { echo "⚠️  No IP found"; return 1; }
    
    LAST_IP_FILE="$XDG_STATE_HOME/access/last_ip"
    LAST_RUN_FILE="$XDG_STATE_HOME/access/last_run"
    ensure_directories
    
    # Record run timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$LAST_RUN_FILE"
    
    if [ -f "$LAST_IP_FILE" ] && [ "$(cat "$LAST_IP_FILE" 2>/dev/null)" = "$ip" ]; then
        echo "🔄 IP unchanged ($ip)"
        return 0
    fi
    
    _dns_host="${HOST:-$DEFAULT_HOST}"
    _dns_domain="${DOMAIN:-$DEFAULT_DOMAIN}"
    _dns_type="A"; case "$ip" in *:*) _dns_type="AAAA";; esac
    
    if curl -s -X PUT "https://api.godaddy.com/v1/domains/$_dns_domain/records/$_dns_type/$_dns_host" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"$ip\",\"ttl\":600}]" >/dev/null; then
        echo "✅ $_dns_host.$_dns_domain → $ip"
        echo "$ip" > "$LAST_IP_FILE"
    else
        echo "❌ Update failed"
        return 1
    fi
}

do_setup() {
    ensure_directories
    printf "Domain [$DEFAULT_DOMAIN]: "; read domain; domain="${domain:-$DEFAULT_DOMAIN}"
    printf "Host [$DEFAULT_HOST]: "; read host; host="${host:-$DEFAULT_HOST}"
    printf "Key: "; read key
    printf "Secret: "; read secret
    
    cat > "$CONFIG_FILE" << EOF
DOMAIN=$domain
HOST=$host
GODADDY_KEY=$key
GODADDY_SECRET=$secret
EOF
    chmod 600 "$CONFIG_FILE"
    echo "✅ Config updated"
    update_dns
}

start_monitor_daemon() {
    echo "🔥 Starting real-time IP monitor..."
    echo "$(date): Starting IP monitor session" >&2
    
    # Direct IP monitoring - systemd handles restarts
    exec ip monitor addr 2>/dev/null | while read line; do
        case "$line" in
            *"scope global"*)
                echo "$(date): IP change detected - $line" >&2
                update_dns || echo "$(date): DNS sync failed, will retry on next change" >&2
                ;;
        esac
    done
}

do_install() {
    echo "🌟 Installing Access..."
    ensure_directories
    
    # Only install if not already in correct location or if different
    if [ "$0" != "$ACCESS_BIN" ]; then
        install_binary "$0"
    fi
    echo "✅ Installed and configured"
    
    # Auto-setup if no config
    [ ! -f "$CONFIG_FILE" ] && do_setup
    
    # Create and start service
    create_service
}

do_upgrade() {
    curl -s https://raw.githubusercontent.com/akaoio/access/main/access.sh > /tmp/access-new
    if [ -s /tmp/access-new ] && head -1 /tmp/access-new | grep -q "#!/bin/sh"; then
        install_binary /tmp/access-new
        echo "✅ Upgraded binary"
        
        # Record upgrade timestamp
        ensure_directories
        UPGRADE_FILE="$XDG_STATE_HOME/access/last_upgrade"
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$UPGRADE_FILE"
        
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

do_status() {
    echo "📊 Access Status"
    echo "================"
    
    # IP info
    current_ip=$(get_ip)
    LAST_IP_FILE="$XDG_STATE_HOME/access/last_ip"
    if [ -f "$LAST_IP_FILE" ]; then
        last_ip=$(cat "$LAST_IP_FILE" 2>/dev/null)
        echo "🌐 Current IP: ${current_ip:-Unknown}"
        echo "📄 Last IP: ${last_ip:-Unknown}"
        if [ "$current_ip" = "$last_ip" ]; then
            echo "✅ IP Status: Unchanged"
        else
            echo "🔄 IP Status: Changed (needs update)"
        fi
    else
        echo "🌐 Current IP: ${current_ip:-Unknown}"
        echo "📄 Last IP: Not recorded"
    fi
    
    # Last run timestamp
    LAST_RUN_FILE="$XDG_STATE_HOME/access/last_run"
    if [ -f "$LAST_RUN_FILE" ]; then
        last_run=$(cat "$LAST_RUN_FILE" 2>/dev/null)
        echo "⏰ Last run: $last_run"
    else
        echo "⏰ Last run: Never"
    fi
    
    # Service status
    echo ""
    echo "🔧 Service Status:"
    if systemctl --user is-active access.service >/dev/null 2>&1; then
        echo "✅ SystemD service: Running"
        service_since=$(systemctl --user show access.service --property=ActiveEnterTimestamp --value 2>/dev/null | cut -d' ' -f1-2)
        echo "   Started: $service_since"
    else
        echo "❌ SystemD service: Not running"
    fi
    
    # Cron status
    cron_count=$(crontab -l 2>/dev/null | grep -c "$ACCESS_BIN" || echo "0")
    echo "📅 Cron jobs: $cron_count installed"
    if [ "$cron_count" -gt 0 ]; then
        echo "   Jobs:"
        crontab -l 2>/dev/null | grep "$ACCESS_BIN" | sed 's/^/   /'
    fi
    
    # Last upgrade
    UPGRADE_FILE="$XDG_STATE_HOME/access/last_upgrade"
    if [ -f "$UPGRADE_FILE" ]; then
        last_upgrade=$(cat "$UPGRADE_FILE" 2>/dev/null)
        echo "🔄 Last upgrade: $last_upgrade"
    else
        echo "🔄 Last upgrade: Never"
    fi
    
    # Config status
    echo ""
    echo "⚙️  Configuration:"
    if [ -f "$CONFIG_FILE" ]; then
        echo "✅ Config file: Found"
        echo "   Domain: ${DOMAIN:-$DEFAULT_DOMAIN}"
        echo "   Host: ${HOST:-$DEFAULT_HOST}"
        echo "   API Key: ${GODADDY_KEY:+Set}${GODADDY_KEY:-Missing}"
    else
        echo "❌ Config file: Missing (run: access setup)"
    fi
}

case "${1:-install}" in
    install) do_install ;;
    setup) do_setup ;;
    sync) update_dns ;;
    update) update_dns ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    _monitor) start_monitor_daemon ;;
    *) echo "Access: install|setup|sync|upgrade|uninstall|status" ;;
esac