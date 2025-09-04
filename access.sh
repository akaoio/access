#!/bin/sh
# Access Eternal - Minimal POSIX dynamic DNS
set -e

# Environment
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
[ -w "/usr/local/bin" ] 2>/dev/null && XDG_BIN_HOME="/usr/local/bin"
ACCESS_BIN="$XDG_BIN_HOME/access"

# Check for config in both user and system locations when running with sudo
if [ "$USER" = "root" ] && [ -n "$SUDO_USER" ]; then
    # When running as root via sudo, check original user's config first
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    USER_CONFIG_FILE="$SUDO_USER_HOME/.config/access/config.env"
    if [ -f "$USER_CONFIG_FILE" ]; then
        CONFIG_FILE="$USER_CONFIG_FILE"
    else
        CONFIG_FILE="$XDG_CONFIG_HOME/access/config.env"
    fi
else
    CONFIG_FILE="$XDG_CONFIG_HOME/access/config.env"
fi

_hostname=$(hostname 2>/dev/null || echo "peer0.akao.io")
DEFAULT_HOST="${_hostname%%.*}"
DEFAULT_DOMAIN="${_hostname#*.}"
[ "$DEFAULT_DOMAIN" = "$DEFAULT_HOST" ] && DEFAULT_DOMAIN="akao.io"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

ensure_directories() {
    if [ "$UID" = "0" ] && [ -n "$SUDO_USER" ]; then
        SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [ -f "$SUDO_USER_HOME/.config/access/config.env" ]; then
            # Ensure user directories exist for state files
            sudo -u "$SUDO_USER" mkdir -p "$SUDO_USER_HOME/.local/state/access"
        fi
    fi
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
    if [ "$UID" = "0" ] || [ "$(id -u)" = "0" ]; then
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
        if systemctl daemon-reload && systemctl enable --now access.service; then
            echo "✅ System service started"
        else
            echo "⚠️ Systemctl failed, trying alternative..."
            # Force enable service files
            ln -sf /etc/systemd/system/access.service /etc/systemd/system/multi-user.target.wants/
            systemctl daemon-reload 2>/dev/null || true
            systemctl start access.service 2>/dev/null || echo "⚠️ Service creation failed - check systemd permissions"
            echo "✅ Service enabled manually"
        fi
        _temp_cron=$(mktemp)
        crontab -l 2>/dev/null | grep -v access > "$_temp_cron" || true
        echo "0 3 * * 0 $ACCESS_BIN upgrade" >> "$_temp_cron"
        echo "*/5 * * * * $ACCESS_BIN sync" >> "$_temp_cron"
        crontab "$_temp_cron" && rm -f "$_temp_cron"
        echo "✅ Cron backup enabled"
        
        # Create system timers for root
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

        if systemctl daemon-reload && systemctl enable access-sync.timer access-upgrade.timer && systemctl start access-sync.timer access-upgrade.timer; then
            echo "✅ System timers enabled"
        else
            echo "⚠️ Timer systemctl failed, enabling manually..."
            # Force enable timer files
            ln -sf /etc/systemd/system/access-sync.timer /etc/systemd/system/timers.target.wants/
            ln -sf /etc/systemd/system/access-upgrade.timer /etc/systemd/system/timers.target.wants/
            systemctl daemon-reload 2>/dev/null || true
            systemctl start access-sync.timer access-upgrade.timer 2>/dev/null || true
            echo "✅ Timers enabled manually"
        fi
    else
        # Force user systemd services to work
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
        if systemctl --user enable --now access.service; then
            echo "✅ Service started"
        else
            echo "⚠️ User systemctl failed, forcing manual enable..."
            # Force create user service symlinks
            mkdir -p "$XDG_CONFIG_HOME/systemd/user/default.target.wants"
            ln -sf "$XDG_CONFIG_HOME/systemd/user/access.service" "$XDG_CONFIG_HOME/systemd/user/default.target.wants/"
            systemctl --user daemon-reload 2>/dev/null || true
            systemctl --user start access.service 2>/dev/null || echo "Manual service start needed"
            echo "✅ Service enabled manually"
        fi
        
        # Create user timers
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

        if systemctl --user daemon-reload && systemctl --user enable access-sync.timer access-upgrade.timer && systemctl --user start access-sync.timer access-upgrade.timer; then
            echo "✅ User timers enabled"
        else
            echo "⚠️ User timer systemctl failed, forcing manual enable..."
            # Force create user timer symlinks
            mkdir -p "$XDG_CONFIG_HOME/systemd/user/timers.target.wants"
            ln -sf "$XDG_CONFIG_HOME/systemd/user/access-sync.timer" "$XDG_CONFIG_HOME/systemd/user/timers.target.wants/"
            ln -sf "$XDG_CONFIG_HOME/systemd/user/access-upgrade.timer" "$XDG_CONFIG_HOME/systemd/user/timers.target.wants/"
            systemctl --user daemon-reload 2>/dev/null || true
            systemctl --user start access-sync.timer access-upgrade.timer 2>/dev/null || true
            echo "✅ User timers enabled manually"
        fi
    fi
}

get_ip() {
    # For IPv6-only networks, prefer stable IPv6 over temporary privacy addresses
    stable_ipv6=$(ip -6 addr show | grep "scope global" | grep -v "temporary" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$stable_ipv6" ]; then
        echo "$stable_ipv6"
        return
    fi
    
    # Fallback to any global IPv6 (including temporary)
    temp_ipv6=$(ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$temp_ipv6" ]; then
        echo "$temp_ipv6"
        return
    fi
    
    # Fallback to IPv4 (likely private/internal only)
    ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1
}

sync_dns() {
    [ -z "$GODADDY_KEY" ] && { echo "⚠️  No config. Run: access setup"; return 1; }
    
    # Use same user's state directory as config when running with sudo
    if [ "$UID" = "0" ] && [ -n "$SUDO_USER" ]; then
        SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        USER_STATE_DIR="$SUDO_USER_HOME/.local/state/access"
        if [ -f "$USER_CONFIG_FILE" ]; then
            LOCK_FILE="$USER_STATE_DIR/sync.lock"
            LAST_IP_FILE="$USER_STATE_DIR/last_ip"
            LAST_RUN_FILE="$USER_STATE_DIR/last_run"
        else
            LOCK_FILE="$XDG_STATE_HOME/access/sync.lock"
            LAST_IP_FILE="$XDG_STATE_HOME/access/last_ip"
            LAST_RUN_FILE="$XDG_STATE_HOME/access/last_run"
        fi
    else
        LOCK_FILE="$XDG_STATE_HOME/access/sync.lock"
        LAST_IP_FILE="$XDG_STATE_HOME/access/last_ip"
        LAST_RUN_FILE="$XDG_STATE_HOME/access/last_run"
    fi
    ensure_directories
    
    # Process lock to prevent concurrent runs
    if ! (
        flock -n 9 || { echo "🔒 Another sync in progress, skipping"; exit 1; }
    ) 9>"$LOCK_FILE"; then
        return 0
    fi
    
    ip=$(get_ip)
    [ -z "$ip" ] && { echo "⚠️  No IP found"; return 1; }
    
    # Check if recent sync happened (within 2 minutes) to avoid redundant runs
    if [ -f "$LAST_RUN_FILE" ]; then
        last_run_time=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
        current_time=$(date '+%Y-%m-%d %H:%M:%S')
        last_epoch=$(date -d "$last_run_time" +%s 2>/dev/null || echo "0")
        current_epoch=$(date -d "$current_time" +%s)
        time_diff=$((current_epoch - last_epoch))
        
        if [ $time_diff -lt 120 ]; then
            echo "🕐 Recent sync ${time_diff}s ago, skipping"
            return 0
        fi
    fi
    
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
    
    # Enable services automatically after setup
    create_service
    sync_dns
}

start_monitor_daemon() {
    echo "🔥 Starting real-time IP monitor..."
    echo "$(date): Starting IP monitor session" >&2
    
    # Robust IP monitoring with error handling
    while true; do
        ip monitor addr 2>/dev/null | while read line; do
            case "$line" in
                *"scope global"*)
                    echo "$(date): IP change detected - $line" >&2
                    sync_dns 2>/dev/null || echo "$(date): DNS sync failed, will retry on next change" >&2
                    ;;
            esac
        done
        echo "$(date): IP monitor exited, restarting in 5 seconds..." >&2
        sleep 5
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
    
    # Create and start service (includes timers)
    create_service
    
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
    
    # Use same logic as sync_dns for state files
    if [ "$UID" = "0" ] && [ -n "$SUDO_USER" ]; then
        SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        USER_STATE_DIR="$SUDO_USER_HOME/.local/state/access"
        if [ -f "$SUDO_USER_HOME/.config/access/config.env" ]; then
            last_ip=$(cat "$USER_STATE_DIR/last_ip" 2>/dev/null || echo "?")
            last_run=$(cat "$USER_STATE_DIR/last_run" 2>/dev/null || echo "Never")
            last_upgrade=$(cat "$USER_STATE_DIR/last_upgrade" 2>/dev/null || echo "Never")
        else
            last_ip=$(cat "$XDG_STATE_HOME/access/last_ip" 2>/dev/null || echo "?")
            last_run=$(cat "$XDG_STATE_HOME/access/last_run" 2>/dev/null || echo "Never")
            last_upgrade=$(cat "$XDG_STATE_HOME/access/last_upgrade" 2>/dev/null || echo "Never")
        fi
    else
        last_ip=$(cat "$XDG_STATE_HOME/access/last_ip" 2>/dev/null || echo "?")
        last_run=$(cat "$XDG_STATE_HOME/access/last_run" 2>/dev/null || echo "Never")
        last_upgrade=$(cat "$XDG_STATE_HOME/access/last_upgrade" 2>/dev/null || echo "Never")
    fi
    
    cat << EOF
📊 ${HOST:-$DEFAULT_HOST}.${DOMAIN:-$DEFAULT_DOMAIN} | IP: ${current_ip:-?} | Last: $last_ip
⏰ Run: $last_run | Upgrade: $last_upgrade
EOF
    
    if [ "$UID" = "0" ] || [ "$(id -u)" = "0" ]; then
        service_status="❌ Down"
        systemctl is-active access.service >/dev/null 2>&1 && service_status="✅ Running"
        
        timer_count=$(systemctl list-timers --all --no-legend 2>/dev/null | grep -c "access.*timer" || echo "0")
        # Check root cron when running as root
        if [ "$UID" = "0" ] || [ "$(id -u)" = "0" ]; then
            cron_jobs=$(crontab -l 2>/dev/null | grep -c access || echo "0")
        else
            cron_jobs=$(sudo crontab -l 2>/dev/null | grep -c access || echo "0")
        fi
        
        echo "✅ System service: $service_status | Timers: $timer_count | Cron: $cron_jobs"
    elif systemctl --user is-active access.service >/dev/null 2>&1; then
        timer_count=$(systemctl --user list-timers --all --no-legend 2>/dev/null | grep -c "access.*timer" || echo "0")
        cron_jobs=$(crontab -l 2>/dev/null | grep -c "$ACCESS_BIN" || echo "0")
        echo "✅ Service: Running | Timers: $timer_count | Cron: $cron_jobs"
    else
        timer_count=$(systemctl --user list-timers --all --no-legend 2>/dev/null | grep -c "access.*timer" || echo "0")
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