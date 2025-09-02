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

# Main command handling
case "${1:-update}" in
    update) update_dns ;;
    ip) get_ip ;;
    *) 
        echo "Access - Eternal Foundation Layer"
        echo "Commands: update, ip"
        ;;
esac