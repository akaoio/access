#!/bin/sh
# Access - Pure shell network access layer
# The eternal foundation that enables connectivity

VERSION="1.0.0"
ACCESS_HOME="${ACCESS_HOME:-$HOME/.access}"
ACCESS_CONFIG="${ACCESS_CONFIG:-$ACCESS_HOME/config.json}"
ACCESS_STATE="${ACCESS_STATE:-$ACCESS_HOME/state.json}"
ACCESS_LOG="${ACCESS_LOG:-$ACCESS_HOME/access.log}"

# Ensure access directory exists
mkdir -p "$ACCESS_HOME"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ACCESS_LOG"
}

# IP validation
validate_ip() {
    echo "$1" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || return 1
    
    # Check each octet
    IFS='.' read -r a b c d <<EOF
$1
EOF
    [ "$a" -le 255 ] && [ "$b" -le 255 ] && [ "$c" -le 255 ] && [ "$d" -le 255 ] || return 1
    
    # Exclude private/reserved ranges
    [ "$a" -eq 10 ] && return 1
    [ "$a" -eq 127 ] && return 1
    [ "$a" -eq 0 ] && return 1
    [ "$a" -ge 224 ] && return 1
    [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ] && return 1
    [ "$a" -eq 192 ] && [ "$b" -eq 168 ] && return 1
    
    return 0
}

# Detect public IP via DNS
detect_ip_dns() {
    local ip=""
    
    # Try OpenDNS
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -n1)
        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Try nslookup
    if command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup myip.opendns.com resolver1.opendns.com 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    return 1
}

# Detect public IP via HTTP
detect_ip_http() {
    local ip=""
    local services="https://checkip.amazonaws.com https://ipv4.icanhazip.com https://ifconfig.me"
    
    for service in $services; do
        # Try curl
        if command -v curl >/dev/null 2>&1; then
            ip=$(curl -s --max-time 5 "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
            if validate_ip "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Try wget
        if command -v wget >/dev/null 2>&1; then
            ip=$(wget -qO- --timeout=5 "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
            if validate_ip "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    return 1
}

# Main IP detection
detect_ip() {
    local ip=""
    
    # Try DNS first (fastest)
    ip=$(detect_ip_dns)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fall back to HTTP
    ip=$(detect_ip_http)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

# Update GoDaddy DNS
update_godaddy() {
    local domain="$1"
    local host="$2"
    local ip="$3"
    local key="$4"
    local secret="$5"
    
    if [ -z "$key" ] || [ -z "$secret" ] || [ -z "$domain" ]; then
        log "ERROR: GoDaddy credentials not configured"
        return 1
    fi
    
    # Get current DNS record
    local current_ip=$(curl -s -X GET \
        "https://api.godaddy.com/v1/domains/$domain/records/A/$host" \
        -H "Authorization: sso-key $key:$secret" | \
        grep -oE '"data":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$current_ip" = "$ip" ]; then
        log "IP unchanged: $ip"
        return 0
    fi
    
    # Update DNS record
    curl -s -X PUT \
        "https://api.godaddy.com/v1/domains/$domain/records/A/$host" \
        -H "Authorization: sso-key $key:$secret" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"$ip\"}]"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS: Updated $host.$domain to $ip"
        return 0
    else
        log "ERROR: Failed to update DNS"
        return 1
    fi
}

# Load configuration
load_config() {
    if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
        # Use jq if available
        PROVIDER=$(jq -r '.provider // "godaddy"' "$ACCESS_CONFIG")
        DOMAIN=$(jq -r '.domain // ""' "$ACCESS_CONFIG")
        HOST=$(jq -r '.host // "@"' "$ACCESS_CONFIG")
        KEY=$(jq -r '.godaddy.key // ""' "$ACCESS_CONFIG")
        SECRET=$(jq -r '.godaddy.secret // ""' "$ACCESS_CONFIG")
    elif [ -f "$ACCESS_CONFIG" ]; then
        # Fallback to grep/sed parsing
        PROVIDER=$(grep '"provider"' "$ACCESS_CONFIG" | sed 's/.*"provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        DOMAIN=$(grep '"domain"' "$ACCESS_CONFIG" | sed 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        HOST=$(grep '"host"' "$ACCESS_CONFIG" | sed 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        # Note: Nested values harder without jq
    fi
    
    # Environment overrides
    PROVIDER="${ACCESS_PROVIDER:-$PROVIDER}"
    DOMAIN="${ACCESS_DOMAIN:-$DOMAIN}"
    HOST="${ACCESS_HOST:-$HOST}"
    KEY="${ACCESS_KEY:-$KEY}"
    SECRET="${ACCESS_SECRET:-$SECRET}"
}

# Save configuration
save_config() {
    cat > "$ACCESS_CONFIG" <<EOF
{
    "provider": "$PROVIDER",
    "domain": "$DOMAIN",
    "host": "$HOST",
    "godaddy": {
        "key": "$KEY",
        "secret": "$SECRET"
    }
}
EOF
    log "Configuration saved to $ACCESS_CONFIG"
}

# Main command handler
case "${1:-help}" in
    ip)
        ip=$(detect_ip)
        if [ $? -eq 0 ]; then
            echo "$ip"
            log "Detected IP: $ip"
        else
            log "ERROR: Failed to detect IP"
            exit 1
        fi
        ;;
        
    update)
        load_config
        ip=$(detect_ip)
        if [ $? -ne 0 ]; then
            log "ERROR: Failed to detect IP"
            exit 1
        fi
        
        log "Detected IP: $ip"
        
        case "$PROVIDER" in
            godaddy)
                update_godaddy "$DOMAIN" "$HOST" "$ip" "$KEY" "$SECRET"
                ;;
            *)
                log "ERROR: Unsupported provider: $PROVIDER"
                exit 1
                ;;
        esac
        ;;
        
    config)
        shift
        PROVIDER="${1:-godaddy}"
        shift
        
        # Parse arguments
        for arg in "$@"; do
            case "$arg" in
                --key=*) KEY="${arg#*=}" ;;
                --secret=*) SECRET="${arg#*=}" ;;
                --domain=*) DOMAIN="${arg#*=}" ;;
                --host=*) HOST="${arg#*=}" ;;
            esac
        done
        
        save_config
        ;;
        
    ssl)
        shift
        # Delegate to ssl.sh script
        if [ -f "$(dirname "$0")/ssl.sh" ]; then
            "$(dirname "$0")/ssl.sh" "$@"
        else
            log "Error: ssl.sh not found"
            exit 1
        fi
        ;;
        
    daemon)
        log "Starting Access daemon..."
        while true; do
            "$0" update
            # Also check SSL certificate expiry
            "$0" ssl check 2>/dev/null || true
            sleep "${ACCESS_INTERVAL:-300}"
        done
        ;;
        
    version)
        echo "Access v$VERSION - Pure shell network access layer"
        ;;
        
    *)
        cat <<EOF
Access - Pure shell network access layer

Usage:
    access ip              Detect and display public IP
    access update          Update DNS with current IP  
    access config          Configure DNS provider
    access ssl             Manage SSL certificates
    access daemon          Run as daemon (updates every 5 minutes)
    access version         Show version
    access help            Show this help

Configuration:
    access config godaddy --key=KEY --secret=SECRET --domain=example.com --host=@
    
SSL Management:
    access ssl generate example.com         Generate self-signed certificate
    access ssl letsencrypt example.com      Setup Let's Encrypt certificate
    access ssl renew                        Renew certificates
    access ssl check                        Check certificate status
    
Environment variables:
    ACCESS_HOME       Config directory (default: ~/.access)
    ACCESS_PROVIDER   DNS provider (default: godaddy)
    ACCESS_DOMAIN     Domain to update
    ACCESS_KEY        Provider API key
    ACCESS_SECRET     Provider API secret
    ACCESS_INTERVAL   Update interval in seconds (default: 300)

EOF
        ;;
esac