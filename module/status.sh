#!/bin/sh
# Status module for Access Eternal - System status display

show_status() {
    # Check for config first
    if [ ! -f "$CONFIG" ]; then
        printf "No config. Please run 'access setup' to configure access.\n"
        return
    fi
    
    # Get current IPs using access command
    current_ipv4=$("$BIN" ip 2>/dev/null | grep "IPv4:" | cut -d' ' -f2)
    current_ipv6=$("$BIN" ip 2>/dev/null | grep "IPv6:" | cut -d' ' -f2)
    
    # Validate current IPs
    if [ "$current_ipv4" = "Not" ] || [ -z "$current_ipv4" ]; then
        current_ipv4="?"
    fi
    if [ "$current_ipv6" = "Not" ] || [ -z "$current_ipv6" ]; then
        current_ipv6="?"
    fi
    
    # Get state file paths
    STATE_DIR="/var/lib/access"
    LAST_IPV4_FILE="$STATE_DIR/last_ipv4"
    LAST_IPV6_FILE="$STATE_DIR/last_ipv6"
    LAST_RUN_FILE="$STATE_DIR/last_run"
    LAST_UPGRADE_FILE="$STATE_DIR/last_upgrade"
    
    # Read state information
    last_ipv4=$(cat "$LAST_IPV4_FILE" 2>/dev/null || echo "?")
    last_ipv6=$(cat "$LAST_IPV6_FILE" 2>/dev/null || echo "?")
    
    # Read timestamp files (now contain epoch seconds)
    if [ -f "$LAST_RUN_FILE" ]; then
        last_run_epoch=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
        if [ "$last_run_epoch" != "0" ] && [ "$last_run_epoch" -gt 0 ] 2>/dev/null; then
            current_epoch=$(date +%s)
            seconds_ago=$((current_epoch - last_run_epoch))
            if [ "$seconds_ago" -lt 60 ]; then
                last_run="${seconds_ago}s ago"
            elif [ "$seconds_ago" -lt 3600 ]; then
                last_run="$((seconds_ago / 60))m ago"
            elif [ "$seconds_ago" -lt 86400 ]; then
                last_run="$((seconds_ago / 3600))h ago"
            else
                last_run="$((seconds_ago / 86400))d ago"
            fi
        else
            last_run="Never"
        fi
    else
        last_run="Never"
    fi
    
    last_upgrade=$(cat "$LAST_UPGRADE_FILE" 2>/dev/null || echo "Never")
    
    # Display status information
    cat << EOF
STATUS: ${HOST:-unknown}.${DOMAIN:-unknown}
IPv4: ${current_ipv4} | Last: ${last_ipv4}
IPv6: ${current_ipv6} | Last: ${last_ipv6}
TIME: Run: $last_run | Upgrade: $last_upgrade
EOF
    
    # Check service status
    if systemctl is-active access.service >/dev/null 2>&1; then
        # System service is running
        service_status="Running"
        timer_count=$(systemctl list-timers --all --no-legend 2>/dev/null | grep -c "access.*timer" || echo "0")
        cron_jobs=$(crontab -l 2>/dev/null | grep -c access || echo "0")
        printf "ACTIVE: System service: %s | Timers: %s | Cron: %s\n" "$service_status" "$timer_count" "$cron_jobs"
    elif systemctl --user is-active access.service >/dev/null 2>&1; then
        timer_count=$(systemctl --user list-timers --all --no-legend 2>/dev/null | grep -c "access.*timer" || echo "0")
        cron_jobs=$(crontab -l 2>/dev/null | grep -c "access" || echo "0")
        printf "ACTIVE: Service: Running | Timers: %s | Cron: %s\n" "$timer_count" "$cron_jobs"
    else
        timer_count=$(systemctl --user list-timers --all --no-legend 2>/dev/null | grep -c "access.*timer" || echo "0")
        cron_jobs=$(crontab -l 2>/dev/null | grep -c "access" || echo "0")
        printf "INACTIVE: Service: Down | Timers: %s | Cron: %s\n" "$timer_count" "$cron_jobs"
    fi
}

main() {
    show_status "$@"
}