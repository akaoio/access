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

provider_update() {
    local domain="$1"
    local host="${2:-@}"
    local ip="$3"
    local key="${GODADDY_KEY}"
    local secret="${GODADDY_SECRET}"
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$ip" ]; then
        echo "Error: Domain and IP required"
        return 1
    fi
    
    # Get current DNS record
    local api_url="https://api.godaddy.com/v1/domains/$domain/records/A/$host"
    local current_ip=$(curl -s -X GET "$api_url" \
        -H "Authorization: sso-key $key:$secret" 2>/dev/null | \
        grep -oE '"data":"[^"]*"' | cut -d'"' -f4)
    
    # Check if update needed
    if [ "$current_ip" = "$ip" ]; then
        echo "[GoDaddy] IP unchanged: $ip"
        return 0
    fi
    
    # Update DNS record
    local response=$(curl -s -w "\n%{http_code}" -X PUT "$api_url" \
        -H "Authorization: sso-key $key:$secret" \
        -H "Content-Type: application/json" \
        -d "[{\"data\": \"$ip\", \"ttl\": 600}]" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "[GoDaddy] Successfully updated $host.$domain to $ip"
        return 0
    else
        echo "[GoDaddy] Failed to update DNS (HTTP $http_code)"
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