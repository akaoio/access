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
    if [ "$USER" = "root" ]; then
        # Root uses system cron, not user systemd
        _temp_cron=$(mktemp)
        crontab -l 2>/dev/null | grep -v access > "$_temp_cron" || true
        echo "0 3 * * 0 $ACCESS_BIN upgrade" >> "$_temp_cron"
        echo "*/5 * * * * $ACCESS_BIN sync" >> "$_temp_cron"
        crontab "$_temp_cron" && rm -f "$_temp_cron"
        echo "✅ Cron setup"
    elif systemctl --user daemon-reload 2>/dev/null; then
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
        echo "✅ Service started"
    else
        _temp_cron=$(mktemp)
        crontab -l 2>/dev/null | grep -v access > "$_temp_cron" || true
        echo "0 3 * * 0 $ACCESS_BIN upgrade" >> "$_temp_cron"
        echo "*/5 * * * * $ACCESS_BIN sync" >> "$_temp_cron"
        crontab "$_temp_cron" && rm -f "$_temp_cron"
        echo "✅ Cron fallback"
    fi
}

get_ip() {
    ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1 ||
    ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1
}

sync_dns() {
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
    echo "✅ Config synced"
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
    sync_dns
}

start_monitor_daemon() {
    echo "🔥 Starting real-time IP monitor..."
    echo "$(date): Starting IP monitor session" >&2
    
    # Direct IP monitoring - systemd handles restarts
    exec ip monitor addr 2>/dev/null | while read line; do
        case "$line" in
            *"scope global"*)
                echo "$(date): IP change detected - $line" >&2
                sync_dns || echo "$(date): DNS sync failed, will retry on next change" >&2
                ;;
        esac
    done
}

do_install() {
    ensure_directories
    [ "$0" != "$ACCESS_BIN" ] && install_binary "$0"
    
    # Auto PATH
    if ! echo "$PATH" | grep -q "$XDG_BIN_HOME"; then
        for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc" "/root/.bashrc" "/root/.profile"; do
            [ -f "$shell_rc" ] && ! grep -q "$XDG_BIN_HOME" "$shell_rc" && {
                echo "export PATH=\"$XDG_BIN_HOME:\$PATH\"" >> "$shell_rc"; break; }
        done
    fi
    export PATH="$XDG_BIN_HOME:$PATH"
    
    # Create basic config if none exists
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
DOMAIN=$DEFAULT_DOMAIN
HOST=$DEFAULT_HOST
GODADDY_KEY=YOUR_KEY_HERE
GODADDY_SECRET=YOUR_SECRET_HERE
EOF
        chmod 600 "$CONFIG_FILE"
        echo "⚠️  Basic config created. Edit $CONFIG_FILE or run: access setup"
    fi
    
    # Create and start service
    create_service
    
    # Ensure command available immediately
    ln -sf "$ACCESS_BIN" "/usr/bin/access" 2>/dev/null || true
}

do_upgrade() {
    curl -s -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/akaoio/access/main/access.sh?$(date +%s)" > /tmp/access-new
    if [ -s /tmp/access-new ] && head -1 /tmp/access-new | grep -q "#!/bin/sh"; then
        # Stop services first
        systemctl --user stop access.service 2>/dev/null || true
        pkill -f "access.*_monitor" 2>/dev/null || true
        
        # Replace binary
        cp /tmp/access-new "$ACCESS_BIN" && chmod +x "$ACCESS_BIN"
        ln -sf "$ACCESS_BIN" "/usr/bin/access" 2>/dev/null || true
        
        # Record upgrade
        ensure_directories
        UPGRADE_FILE="$XDG_STATE_HOME/access/last_upgrade"
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$UPGRADE_FILE"
        
        # Restart services 
        create_service
        echo "✅ Upgraded"
    fi
    rm -f /tmp/access-new
}

do_uninstall() {
    # Stop services
    systemctl --user stop access.service 2>/dev/null || true
    pkill -f "access.*_monitor" 2>/dev/null || true
    
    # Clean cron first
    _temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$_temp_cron" || true
    if [ -s "$_temp_cron" ]; then
        grep -v access "$_temp_cron" > "$_temp_cron.new" || touch "$_temp_cron.new"
        if [ -s "$_temp_cron.new" ]; then
            crontab "$_temp_cron.new"
        else
            crontab -r 2>/dev/null || true
        fi
        rm -f "$_temp_cron.new"
    else
        crontab -r 2>/dev/null || true
    fi
    rm -f "$_temp_cron"
    
    # Clean config and service files
    rm -rf "$XDG_CONFIG_HOME/access" "$XDG_STATE_HOME/access" "$XDG_CONFIG_HOME/systemd/user/access.service"
    
    # Self-destruct - remove binaries last (this will kill current process)
    rm -f "/usr/bin/access" "$ACCESS_BIN"
    echo "✅ Removed"
}

do_status() {
    current_ip=$(get_ip)
    last_ip=$(cat "$XDG_STATE_HOME/access/last_ip" 2>/dev/null || echo "?")
    last_run=$(cat "$XDG_STATE_HOME/access/last_run" 2>/dev/null || echo "Never")
    last_upgrade=$(cat "$XDG_STATE_HOME/access/last_upgrade" 2>/dev/null || echo "Never")
    
    echo "📊 ${HOST:-$DEFAULT_HOST}.${DOMAIN:-$DEFAULT_DOMAIN} | IP: ${current_ip:-?} | Last: $last_ip"
    echo "⏰ Run: $last_run | Upgrade: $last_upgrade"
    
    if [ "$USER" = "root" ]; then
        cron_jobs=$(crontab -l 2>/dev/null | grep -c access || echo "0")
        echo "✅ Root cron: $cron_jobs jobs"
    elif systemctl --user is-active access.service >/dev/null 2>&1; then
        cron_jobs=$(crontab -l 2>/dev/null | grep -c "$ACCESS_BIN" || echo "0")
        echo "✅ Service: Running | Cron: $cron_jobs jobs"
    else
        cron_jobs=$(crontab -l 2>/dev/null | grep -c "$ACCESS_BIN" || echo "0")
        echo "❌ Service: Down | Cron: $cron_jobs jobs"
    fi
    
    [ ! -f "$CONFIG_FILE" ] && echo "⚠️  No config (run: access setup)"
}

case "${1:-install}" in
    install) do_install ;;
    setup) do_setup ;;
    sync) sync_dns ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    _monitor) start_monitor_daemon ;;
    *) echo "Access: install|setup|sync|upgrade|uninstall|status" ;;
esac