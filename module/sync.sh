#!/bin/sh
# Sync module for Access Eternal - DNS synchronization

sync_dns() {
    # Check if config file exists and is readable
    if [ ! -f "$CONFIG" ] || [ ! -r "$CONFIG" ]; then
        printf "WARNING: No config file found at %s\n" "$CONFIG"
        return 6
    fi

    if [ ! -f "$LIB/module/provider/$PROVIDER.sh" ]; then
        printf "WARNING: Unknown provider '%s'\n" "$PROVIDER"
        return 6
    fi
    . "$LIB/module/provider/$PROVIDER.sh"

    # Check required variables
    provider_validate || return $?
    [ -z "$DOMAIN" ] && { printf "WARNING: No DOMAIN configured\n"; return 6; }
    [ -z "$HOST" ] && { printf "WARNING: No HOST configured\n"; return 6; }

    # Ensure state directory exists
    mkdir -p "$STATE" 2>/dev/null || true

    LOCK_FILE="$STATE/sync.lock"
    # Namespaced by provider: switching provider (even with an unchanged IP)
    # must not be skipped as a false "unchanged" dedup match against the
    # previous provider's last-synced state.
    LAST_IPV4_FILE="$STATE/last_ipv4_$PROVIDER"
    LAST_IPV6_FILE="$STATE/last_ipv6_$PROVIDER"
    
    # Hold the lock on fd 9 for the rest of the process, not just a subshell
    # check: daemon, systemd timer and cron can all fire at once, and an
    # overlapping run is what creates duplicate DNS records upstream. The fd
    # (and lock) is released automatically when the process exits.
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        printf "LOCK: Another sync in progress, skipping\n"
        return 0
    fi
    
    # Get current IPv4 and IPv6 addresses. One `access ip` invocation only:
    # each run costs external HTTP lookups, so don't pay for it twice.
    _ip_out=$("$BIN" ip 2>/dev/null) || _ip_out=""
    ipv4=$(printf "%s\n" "$_ip_out" | grep "IPv4:" | cut -d' ' -f2)
    ipv6=$(printf "%s\n" "$_ip_out" | grep "IPv6:" | cut -d' ' -f2)
    
    # Validate IPs
    if [ "$ipv4" = "Not" ] || [ -z "$ipv4" ]; then
        ipv4=""
    fi
    if [ "$ipv6" = "Not" ] || [ -z "$ipv6" ]; then
        ipv6=""
    fi
    
    # Check if we have at least one valid IP
    if [ -z "$ipv4" ] && [ -z "$ipv6" ]; then
        printf "WARNING: No valid IP found\n"
        return 1
    fi
    
    # Track sync status
    sync_success=0
    
    # Sync IPv4 (A record) if available
    if [ -n "$ipv4" ]; then
        last_ipv4=$(cat "$LAST_IPV4_FILE" 2>/dev/null || echo "")
        if [ "$ipv4" != "$last_ipv4" ]; then
            if provider_update_record A "$ipv4"; then
                printf "SUCCESS: %s.%s -> %s (A)\n" "$HOST" "$DOMAIN" "$ipv4"
                printf "%s\n" "$ipv4" > "$LAST_IPV4_FILE"
                sync_success=1
            else
                printf "ERROR: IPv4 update failed\n"
            fi
        else
            printf "SYNC: IPv4 unchanged (%s)\n" "$ipv4"
        fi
    fi
    
    # Sync IPv6 (AAAA record) if available
    if [ -n "$ipv6" ]; then
        last_ipv6=$(cat "$LAST_IPV6_FILE" 2>/dev/null || echo "")
        if [ "$ipv6" != "$last_ipv6" ]; then
            if provider_update_record AAAA "$ipv6"; then
                printf "SUCCESS: %s.%s -> %s (AAAA)\n" "$HOST" "$DOMAIN" "$ipv6"
                printf "%s\n" "$ipv6" > "$LAST_IPV6_FILE"
                sync_success=1
            else
                printf "ERROR: IPv6 update failed\n"
            fi
        else
            printf "SYNC: IPv6 unchanged (%s)\n" "$ipv6"
        fi
    fi
    
    # Record timestamp after successful sync
    if [ "$sync_success" -eq 1 ]; then
        log_time=$(date +%s)
        printf "%s\n" "$log_time" > "$STATE/last_run"
    fi
}

main() {
    sync_dns "$@"
}