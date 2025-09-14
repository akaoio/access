#!/bin/sh
# Sync module for Access Eternal - DNS synchronization

sync_dns() {
    # Check if config file exists and is readable
    if [ ! -f "$CONFIG" ] || [ ! -r "$CONFIG" ]; then
        printf "WARNING: No config file found at %s\n" "$CONFIG"
        return 6
    fi
    
    # Check required variables
    [ -z "$GODADDY_KEY" ] && { printf "WARNING: No GODADDY_KEY configured\n"; return 6; }
    [ -z "$GODADDY_SECRET" ] && { printf "WARNING: No GODADDY_SECRET configured\n"; return 6; }
    [ -z "$DOMAIN" ] && { printf "WARNING: No DOMAIN configured\n"; return 6; }
    [ -z "$HOST" ] && { printf "WARNING: No HOST configured\n"; return 6; }
    
    # Ensure state directory exists
    STATE_DIR="/var/lib/access"
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    
    LOCK_FILE="$STATE_DIR/sync.lock"
    LAST_IP_FILE="$STATE_DIR/last_ip"
    LAST_RUN_FILE="$STATE_DIR/last_run"
    
    # Process lock to prevent concurrent runs
    if ! (
        flock -n 9 || { printf "LOCK: Another sync in progress, skipping\n"; exit 1; }
    ) 9>"$LOCK_FILE"; then
        return 0
    fi
    
    # Get current IP using access command
    ip=$("$BIN" ip 2>/dev/null | grep "IPv6:" | cut -d' ' -f2)
    if [ -z "$ip" ] || [ "$ip" = "Not available" ]; then
        ip=$("$BIN" ip 2>/dev/null | grep "IPv4:" | cut -d' ' -f2)
    fi
    
    [ -z "$ip" ] && { printf "WARNING: No IP found\n"; return 1; }
    
    # Check if IP changed first (before timestamp)
    if [ -f "$LAST_IP_FILE" ] && [ "$(cat "$LAST_IP_FILE" 2>/dev/null)" = "$ip" ]; then
        printf "SYNC: IP unchanged (%s)\n" "$ip"
        return 0
    fi
    
    # Check if recent sync happened (within 2 minutes) to avoid redundant runs
    current_epoch=$(date +%s)
    if [ -f "$LAST_RUN_FILE" ]; then
        last_epoch=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
        time_diff=$((current_epoch - last_epoch))
        
        if [ "$time_diff" -lt 120 ]; then
            printf "SKIP: Recent sync %ss ago, skipping\n" "$time_diff"
            return 0
        fi
    fi
    
    # Determine DNS record type based on IP format
    dns_type="A"
    case "$ip" in *:*) dns_type="AAAA";; esac
    
    # Update DNS via GoDaddy API
    if curl -s -X PUT "https://api.godaddy.com/v1/domains/$DOMAIN/records/$dns_type/$HOST" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"$ip\",\"ttl\":600}]" >/dev/null; then
        printf "SUCCESS: %s.%s -> %s\n" "$HOST" "$DOMAIN" "$ip"
        printf "%s\n" "$ip" > "$LAST_IP_FILE"
        # Record timestamp only after successful sync
        printf "%s\n" "$current_epoch" > "$LAST_RUN_FILE"
    else
        printf "ERROR: Update failed\n"
        return 1
    fi
}

main() {
    sync_dns "$@"
}