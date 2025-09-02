#!/bin/sh
# GoDaddy DNS Provider
# API Documentation: https://developer.godaddy.com/doc/endpoint/domains

provider_info() {
    echo "name: GoDaddy"
    echo "version: 1.0.0"
    echo "author: Access Team"
    echo "type: dns"
    echo "description: GoDaddy Domains API v1"
}

provider_config() {
    echo "field: key, type: string, required: true, description: GoDaddy API Key"
    echo "field: secret, type: string, required: true, description: GoDaddy API Secret"
    echo "field: domain, type: string, required: true, description: Domain to update"
    echo "field: host, type: string, required: false, default: @, description: Host record"
}

provider_validate() {
    if [ -z "${GODADDY_KEY}" ] || [ -z "${GODADDY_SECRET}" ]; then
        echo "Error: GoDaddy API credentials not configured"
        return 1
    fi
    return 0
}

# Validation functions
validate_domain_name() {
    local domain="$1"
    echo "$domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
}

validate_hostname() {
    local host="$1"
    [ "$host" = "@" ] || echo "$host" | grep -qE '^[a-zA-Z0-9.-]+$'
}

validate_ip_address() {
    local ip="$1"
    # IPv4 or IPv6 validation
    echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F]*:)+[0-9a-fA-F]*$'
}

provider_update() {
    local domain="$1"
    local host="${2:-@}"
    local ip="$3"
    local record_type="${4:-}"  # Optional 4th parameter
    local key="${GODADDY_KEY}"
    local secret="${GODADDY_SECRET}"
    
    # SECURITY FIX 4: Input validation to prevent DNS provider injection
    if ! validate_domain_name "$domain"; then
        echo "Error: Invalid domain name: $domain" >&2
        return 1
    fi
    
    if ! validate_hostname "$host"; then
        echo "Error: Invalid hostname: $host" >&2
        return 1
    fi
    
    if ! validate_ip_address "$ip"; then
        echo "Error: Invalid IP address: $ip" >&2
        return 1
    fi
    
    # Auto-detect record type if not provided (backwards compatibility)
    if [ -z "$record_type" ]; then
        if echo "$ip" | grep -q ':'; then
            record_type="AAAA"
        else
            record_type="A"
        fi
    fi
    
    # Validate record type
    case "$record_type" in
        A|AAAA|CNAME|TXT|MX|NS|SRV|PTR)
            # Valid DNS record types
            ;;
        *)
            echo "Error: Invalid DNS record type: $record_type" >&2
            return 1
            ;;
    esac
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$ip" ] || [ -z "$record_type" ]; then
        echo "Error: Domain, IP, and record type required"
        return 1
    fi
    
    echo "[GoDaddy] Updating $record_type record for $host.$domain with IP: $ip"
    
    # Get current DNS record
    local api_url="https://api.godaddy.com/v1/domains/$domain/records/$record_type/$host"
    local current_ip=$(curl -s -X GET "$api_url" \
        -H "Authorization: sso-key $key:$secret" 2>/dev/null | \
        grep -oE '"data":"[^"]*"' | cut -d'"' -f4)
    
    # Check if update needed
    if [ "$current_ip" = "$ip" ]; then
        echo "[GoDaddy] $record_type record unchanged: $ip"
        return 0
    fi
    
    # Update DNS record
    local response=$(curl -s -w "\n%{http_code}" -X PUT "$api_url" \
        -H "Authorization: sso-key $key:$secret" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"$ip\", \"ttl\": 600}]" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "[GoDaddy] Successfully updated $record_type record $host.$domain to $ip"
        return 0
    else
        echo "[GoDaddy] Failed to update $record_type record (HTTP $http_code)"
        echo "[GoDaddy] Response: $(echo "$response" | head -n -1)"
        return 1
    fi
}


provider_test() {
    local domain="${1:-${GODADDY_DOMAIN}}"
    local key="${GODADDY_KEY}"
    local secret="${GODADDY_SECRET}"
    
    if [ -z "$key" ] || [ -z "$secret" ]; then
        echo "Error: Credentials not configured"
        return 1
    fi
    
    # Test API connectivity
    local response=$(curl -s -w "\n%{http_code}" \
        "https://api.godaddy.com/v1/domains" \
        -H "Authorization: sso-key $key:$secret" 2>/dev/null | tail -n1)
    
    if [ "$response" = "200" ]; then
        echo "[GoDaddy] API connection successful"
        return 0
    else
        echo "[GoDaddy] API connection failed (HTTP $response)"
        return 1
    fi
}