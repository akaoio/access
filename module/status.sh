#!/bin/sh
# Status module for Access Eternal - System status display

# Print "<n>s/m/h/d ago" for an epoch-seconds value, or "Never" if missing/invalid
humanize_epoch() {
    _epoch="$1"
    if [ -n "$_epoch" ] && [ "$_epoch" -gt 0 ] 2>/dev/null; then
        _ago=$(($(date +%s) - _epoch))
        if [ "$_ago" -lt 60 ]; then
            printf "%ss ago" "$_ago"
        elif [ "$_ago" -lt 3600 ]; then
            printf "%sm ago" "$((_ago / 60))"
        elif [ "$_ago" -lt 86400 ]; then
            printf "%sh ago" "$((_ago / 3600))"
        else
            printf "%sd ago" "$((_ago / 86400))"
        fi
    else
        printf "Never"
    fi
}

# Colors only when stdout is a terminal (empty when piped/redirected)
if [ -t 1 ]; then
    C_OK=$(printf '\033[32m')
    C_BAD=$(printf '\033[31m')
    C_WARN=$(printf '\033[33m')
    C_DIM=$(printf '\033[2m')
    C_OFF=$(printf '\033[0m')
else
    C_OK=""; C_BAD=""; C_WARN=""; C_DIM=""; C_OFF=""
fi

# $1 = current IP, $2 = last-synced IP -> short note instead of dumping both
sync_note() {
    if [ "$1" = "?" ]; then
        printf "%s(unavailable)%s" "$C_DIM" "$C_OFF"
    elif [ "$2" = "?" ]; then
        printf "%s(never synced)%s" "$C_WARN" "$C_OFF"
    elif [ "$1" = "$2" ]; then
        printf "%s(synced)%s" "$C_OK" "$C_OFF"
    else
        printf "%s(DNS has %s)%s" "$C_BAD" "$2" "$C_OFF"
    fi
}

show_status() {
    # Check for config first
    if [ ! -f "$CONFIG" ]; then
        printf "No config found at %s. Run install.sh to configure Access.\n" "$CONFIG"
        return
    fi
    
    # Get current IPs using a single access invocation (each run costs
    # external HTTP lookups)
    _ip_out=$("$BIN" ip 2>/dev/null) || _ip_out=""
    current_ipv4=$(printf "%s\n" "$_ip_out" | grep "IPv4:" | cut -d' ' -f2)
    current_ipv6=$(printf "%s\n" "$_ip_out" | grep "IPv6:" | cut -d' ' -f2)
    
    # Validate current IPs
    if [ "$current_ipv4" = "Not" ] || [ -z "$current_ipv4" ]; then
        current_ipv4="?"
    fi
    if [ "$current_ipv6" = "Not" ] || [ -z "$current_ipv6" ]; then
        current_ipv6="?"
    fi
    
    # Get state file paths (namespaced by provider, see module/sync.sh)
    LAST_IPV4_FILE="$STATE/last_ipv4_$PROVIDER"
    LAST_IPV6_FILE="$STATE/last_ipv6_$PROVIDER"
    LAST_RUN_FILE="$STATE/last_run"
    LAST_UPGRADE_FILE="$STATE/last_upgrade"
    
    # Read state information
    last_ipv4=$(cat "$LAST_IPV4_FILE" 2>/dev/null || echo "?")
    last_ipv6=$(cat "$LAST_IPV6_FILE" 2>/dev/null || echo "?")
    
    # Both timestamp files contain epoch seconds - humanize them the same way
    last_run=$(humanize_epoch "$(cat "$LAST_RUN_FILE" 2>/dev/null)")
    last_upgrade=$(humanize_epoch "$(cat "$LAST_UPGRADE_FILE" 2>/dev/null)")

    # Check service status. Access only installs as a system service (FHS
    # layout), so there is no --user variant to probe. grep -c exits nonzero
    # on zero matches, so fall back via || (the dispatcher runs under set -e).
    timer_count=$(systemctl list-timers --all --no-legend 2>/dev/null | grep -c "access.*timer") || timer_count=0
    cron_jobs=$(crontab -l 2>/dev/null | grep -c access) || cron_jobs=0
    if systemctl is-active access.service >/dev/null 2>&1; then
        service_line="${C_OK}running${C_OFF}"
    else
        service_line="${C_BAD}down${C_OFF}"
    fi

    # One fact per line so nothing wraps into the next field on narrow terminals
    printf "\n"
    printf "  %s.%s %s(%s)%s\n" "${HOST:-unknown}" "${DOMAIN:-unknown}" "$C_DIM" "$PROVIDER" "$C_OFF"
    printf "\n"
    printf "  %-13s%-16s %s\n" "IPv4:" "$current_ipv4" "$(sync_note "$current_ipv4" "$last_ipv4")"
    printf "  %-13s%s %s\n" "IPv6:" "$current_ipv6" "$(sync_note "$current_ipv6" "$last_ipv6")"
    printf "\n"
    printf "  %-13s%s\n" "Last sync:" "$last_run"
    printf "  %-13s%s\n" "Last update:" "$last_upgrade"
    printf "\n"
    printf "  %-13s%s\n" "Service:" "$service_line"
    printf "  %-13s%s\n" "Timers:" "$timer_count"
    printf "  %-13s%s\n" "Cron jobs:" "$cron_jobs"
    printf "\n"
}

main() {
    show_status "$@"
}