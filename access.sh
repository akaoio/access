#!/bin/sh
# Access - Eternal Foundation Layer
# Pure POSIX shell implementation - zero dependencies
# "When everything fails, Access survives"

set -e

# Configuration from environment
CONFIG_FILE="${ACCESS_CONFIG:-$HOME/.config/access/config.env}"

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Required variables with defaults
PROVIDER="${PROVIDER:-godaddy}"
DOMAIN="${DOMAIN:-akao.io}"
HOST="${HOST:-peer0}"

# Validate essential config
if [ -z "$GODADDY_KEY" ] || [ -z "$GODADDY_SECRET" ]; then
    echo "ERROR: Missing GODADDY_KEY or GODADDY_SECRET in $CONFIG_FILE"
    exit 1
fi

# Get current IP
get_ip() {
    curl -s ifconfig.me || curl -s ipinfo.io/ip || {
        echo "ERROR: Cannot detect IP"
        exit 1
    }
}

# Update GoDaddy DNS record
update_dns() {
    local ip="$(get_ip)"
    local record_type="A"
    
    # Detect IPv6
    case "$ip" in
        *:*) record_type="AAAA" ;;
    esac
    
    echo "Updating $HOST.$DOMAIN ($record_type) to $ip"
    
    # GoDaddy API call
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        "https://api.godaddy.com/v1/domains/$DOMAIN/records/$record_type/$HOST" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"$ip\", \"ttl\": 600}]")
    
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "✅ DNS updated successfully"
    else
        echo "❌ DNS update failed (HTTP $http_code)"
        exit 1
    fi
}

# Real-time IP monitoring (POSIX + XDG)
monitor_ip() {
    echo "Starting real-time IP monitoring..."
    
    # XDG state directory for IP tracking
    STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/access"
    mkdir -p "$STATE_DIR"
    IP_STATE_FILE="$STATE_DIR/current_ip"
    
    # Initialize with current IP
    current_ip=$(get_ip)
    echo "$current_ip" > "$IP_STATE_FILE"
    echo "Initial IP: $current_ip"
    
    # Monitor network changes using pure POSIX
    while true; do
        new_ip=$(get_ip)
        
        if [ "$new_ip" != "$current_ip" ]; then
            echo "IP changed: $current_ip → $new_ip"
            echo "$new_ip" > "$IP_STATE_FILE"
            
            # Instant DNS update
            echo "Triggering instant DNS update..."
            update_dns
            
            current_ip="$new_ip"
            echo "$(date): Real-time update complete"
        fi
        
        # Check every 30 seconds (balance between real-time and resources)
        sleep 30
    done
}

# Main command handling
case "${1:-update}" in
    update) update_dns ;;
    monitor) monitor_ip ;;
    ip) get_ip ;;
    *) 
        echo "Access - Eternal Foundation Layer"
        echo "Commands: update, monitor, ip"
        ;;
esac