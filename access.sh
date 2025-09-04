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
        # Root: create both system service and cron for redundancy
        cat > "/etc/systemd/system/access.service" << EOF
[Unit]
Description=Access IP Monitor
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=$ACCESS_BIN _monitor
StandardOutput=append:/var/log/access.log
StandardError=append:/var/log/access.log

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload && systemctl enable --now access.service
        echo "✅ System service started"
        
        # Always create cron as backup
        _temp_cron=$(mktemp)
        crontab -l 2>/dev/null | grep -v access > "$_temp_cron" || true
        echo "0 3 * * 0 $ACCESS_BIN upgrade" >> "$_temp_cron"
        echo "*/5 * * * * $ACCESS_BIN sync" >> "$_temp_cron"
        crontab "$_temp_cron" && rm -f "$_temp_cron"
        echo "✅ Cron backup enabled"
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

create_timers() {
    if [ "$USER" = "root" ]; then
        # Root: create system timers
        cat > "/etc/systemd/system/access-sync.service" << EOF
[Unit]
Description=Access DNS Sync
After=network.target

[Service]
Type=oneshot
ExecStart=$ACCESS_BIN sync
StandardOutput=append:/var/log/access.log
StandardError=append:/var/log/access.log
EOF

        cat > "/etc/systemd/system/access-sync.timer" << EOF
[Unit]
Description=Access DNS Sync Timer (5min backup)
Requires=access-sync.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

        cat > "/etc/systemd/system/access-upgrade.service" << EOF
[Unit]
Description=Access Auto Upgrade
After=network.target

[Service]
Type=oneshot
ExecStart=$ACCESS_BIN upgrade
StandardOutput=append:/var/log/access.log
StandardError=append:/var/log/access.log
EOF

        cat > "/etc/systemd/system/access-upgrade.timer" << EOF
[Unit]
Description=Access Auto Upgrade Timer (weekly)
Requires=access-upgrade.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

        systemctl daemon-reload
        systemctl enable --now access-sync.timer access-upgrade.timer
        echo "✅ System timers enabled"
        
    elif systemctl --user daemon-reload 2>/dev/null; then
        ensure_directories
        cat > "$XDG_CONFIG_HOME/systemd/user/access-sync.service" << EOF
[Unit]
Description=Access DNS Sync

[Service]
Type=oneshot
ExecStart=$ACCESS_BIN sync
StandardOutput=append:$XDG_STATE_HOME/access/access.log
StandardError=append:$XDG_STATE_HOME/access/error.log
EOF

        cat > "$XDG_CONFIG_HOME/systemd/user/access-sync.timer" << EOF
[Unit]
Description=Access DNS Sync Timer (5min backup)
Requires=access-sync.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

        cat > "$XDG_CONFIG_HOME/systemd/user/access-upgrade.service" << EOF
[Unit]
Description=Access Auto Upgrade

[Service]
Type=oneshot
ExecStart=$ACCESS_BIN upgrade
StandardOutput=append:$XDG_STATE_HOME/access/access.log
StandardError=append:$XDG_STATE_HOME/access/error.log
EOF

        cat > "$XDG_CONFIG_HOME/systemd/user/access-upgrade.timer" << EOF
[Unit]
Description=Access Auto Upgrade Timer (weekly)
Requires=access-upgrade.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

        systemctl --user daemon-reload
        systemctl --user enable --now access-sync.timer access-upgrade.timer
        echo "✅ User timers enabled"
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
    
    # Create and start timers in parallel to cron
    create_timers
    
    # Ensure command available immediately
    ln -sf "$ACCESS_BIN" "/usr/bin/access" 2>/dev/null || true
}

do_upgrade() {
    curl -s -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/akaoio/access/main/access.sh?$(date +%s)" > /tmp/access-new
    if [ -s /tmp/access-new ] && head -1 /tmp/access-new | grep -q "#!/bin/sh"; then
        # Stop services and timers first
        systemctl --user stop access.service access-sync.timer access-upgrade.timer 2>/dev/null || true
        systemctl stop access.service access-sync.timer access-upgrade.timer 2>/dev/null || true
        pkill -f "access.*_monitor" 2>/dev/null || true
        
        # Replace binary
        cp /tmp/access-new "$ACCESS_BIN" && chmod +x "$ACCESS_BIN"
        ln -sf "$ACCESS_BIN" "/usr/bin/access" 2>/dev/null || true
        
        # Record upgrade
        ensure_directories
        UPGRADE_FILE="$XDG_STATE_HOME/access/last_upgrade"
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$UPGRADE_FILE"
        
        # Re-run full install to ensure services are properly configured
        chmod +x /tmp/access-new && /tmp/access-new install
        echo "✅ Upgraded"
    fi
    rm -f /tmp/access-new
}

do_uninstall() {
    # Stop services and timers
    systemctl --user stop access.service access-sync.timer access-upgrade.timer 2>/dev/null || true
    systemctl stop access.service access-sync.timer access-upgrade.timer 2>/dev/null || true
    systemctl disable access.service access-sync.timer access-upgrade.timer 2>/dev/null || true
    systemctl --user disable access-sync.timer access-upgrade.timer 2>/dev/null || true
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
    
    # Clean config, service and timer files
    rm -rf "$XDG_CONFIG_HOME/access" "$XDG_STATE_HOME/access" "$XDG_CONFIG_HOME/systemd/user/access.service"
    rm -f "$XDG_CONFIG_HOME/systemd/user/access-sync.service" "$XDG_CONFIG_HOME/systemd/user/access-sync.timer"
    rm -f "$XDG_CONFIG_HOME/systemd/user/access-upgrade.service" "$XDG_CONFIG_HOME/systemd/user/access-upgrade.timer"
    rm -f "/etc/systemd/system/access.service" "/etc/systemd/system/access-sync.service" "/etc/systemd/system/access-sync.timer"
    rm -f "/etc/systemd/system/access-upgrade.service" "/etc/systemd/system/access-upgrade.timer"
    
    # Self-destruct - remove binaries last (this will kill current process) 
    sudo rm -f "/usr/bin/access" 2>/dev/null || rm -f "/usr/bin/access" 2>/dev/null || true
    rm -f "$ACCESS_BIN"
    echo "✅ Removed"
}

do_status() {
    exec >&1
    current_ip=$(get_ip)
    last_ip=$(cat "$XDG_STATE_HOME/access/last_ip" 2>/dev/null || echo "?")
    last_run=$(cat "$XDG_STATE_HOME/access/last_run" 2>/dev/null || echo "Never")
    last_upgrade=$(cat "$XDG_STATE_HOME/access/last_upgrade" 2>/dev/null || echo "Never")
    
    cat << EOF
📊 ${HOST:-$DEFAULT_HOST}.${DOMAIN:-$DEFAULT_DOMAIN} | IP: ${current_ip:-?} | Last: $last_ip
⏰ Run: $last_run | Upgrade: $last_upgrade
EOF
    
    if [ "$USER" = "root" ]; then
        service_status="❌ Down"
        systemctl is-active access.service >/dev/null 2>&1 && service_status="✅ Running"
        
        timer_count=$(systemctl list-timers access-*.timer --no-legend 2>/dev/null | wc -l)
        cron_jobs=$(crontab -l 2>/dev/null | grep -c access || echo "0")
        
        echo "✅ System service: $service_status | Timers: $timer_count | Cron: $cron_jobs"
    elif systemctl --user is-active access.service >/dev/null 2>&1; then
        timer_count=$(systemctl --user list-timers access-*.timer --no-legend 2>/dev/null | wc -l)
        cron_jobs=$(crontab -l 2>/dev/null | grep -c "$ACCESS_BIN" || echo "0")
        echo "✅ Service: Running | Timers: $timer_count | Cron: $cron_jobs"
    else
        timer_count=$(systemctl --user list-timers access-*.timer --no-legend 2>/dev/null | wc -l)
        cron_jobs=$(crontab -l 2>/dev/null | grep -c "$ACCESS_BIN" || echo "0")
        echo "❌ Service: Down | Timers: $timer_count | Cron: $cron_jobs"
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