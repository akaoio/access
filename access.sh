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
    mkdir -p "$XDG_CONFIG_HOME/access" "$XDG_STATE_HOME/access" "$XDG_BIN_HOME"
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
    ensure_directories
    
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
    exec ip monitor addr | while read line; do
        case "$line" in *"scope global"*) update_dns;; esac
    done
}

do_install() {
    ensure_directories
    [ "$0" != "$ACCESS_BIN" ] && cp "$0" "$ACCESS_BIN" && chmod +x "$ACCESS_BIN"
    
    # Auto PATH
    if ! echo "$PATH" | grep -q "$XDG_BIN_HOME"; then
        for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [ -f "$shell_rc" ] && ! grep -q "$XDG_BIN_HOME" "$shell_rc" && {
                echo "export PATH=\"$XDG_BIN_HOME:\$PATH\"" >> "$shell_rc"; break; }
        done
    fi
    export PATH="$XDG_BIN_HOME:$PATH"
    
    # Auto config
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
DOMAIN=$DEFAULT_DOMAIN
HOST=$DEFAULT_HOST
GODADDY_KEY=gd_key_$(date +%s | tail -c 6)
GODADDY_SECRET=gd_secret_$(date +%s | tail -c 6)
EOF
        chmod 600 "$CONFIG_FILE"
        echo "✅ Config: $DEFAULT_HOST.$DEFAULT_DOMAIN"
    fi
    
    # Start monitoring
    command -v ip >/dev/null && nohup sh -c 'exec ip monitor addr | while read line; do case "$line" in *"scope global"*) '"$ACCESS_BIN"' update;; esac; done' >/dev/null 2>&1 &
    
    # Cron
    _temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v access > "$_temp_cron" || true
    echo "0 3 * * 0 $ACCESS_BIN upgrade" >> "$_temp_cron"
    echo "*/1 * * * * $ACCESS_BIN update" >> "$_temp_cron"
    crontab "$_temp_cron"; rm -f "$_temp_cron"
    echo "✅ Installed"
}

do_upgrade() {
    curl -s https://raw.githubusercontent.com/akaoio/access/main/access.sh > /tmp/access-new
    [ -s /tmp/access-new ] && {
        pkill -f "ip monitor" 2>/dev/null || true
        cp /tmp/access-new "$ACCESS_BIN" && chmod +x "$ACCESS_BIN"
        nohup sh -c 'exec ip monitor addr | while read line; do case "$line" in *"scope global"*) '"$ACCESS_BIN"' update;; esac; done' >/dev/null 2>&1 &
        echo "✅ Upgraded"
    }
    rm -f /tmp/access-new
}

do_uninstall() {
    pkill -f "ip monitor" 2>/dev/null || true
    rm -f "$ACCESS_BIN"
    _temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v access > "$_temp_cron" || true
    crontab "$_temp_cron"; rm -f "$_temp_cron"
    echo "✅ Uninstalled"
}

case "${1:-install}" in
    install) do_install ;;
    setup) do_setup ;;
    update) update_dns ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    _monitor) start_monitor_daemon ;;
    *) echo "Access: install|setup|update|upgrade|uninstall" ;;
esac