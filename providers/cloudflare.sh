#!/bin/sh
# Cloudflare DNS Provider
# API Documentation: https://api.cloudflare.com/

provider_info() {
    echo "name: Cloudflare"
    echo "version: 1.0.0"
    echo "author: Access Team"
    echo "type: dns"
    echo "description: Cloudflare API v4"
}

provider_config() {
    echo "field: email, type: string, required: true, description: Cloudflare account email"
    echo "field: api_key, type: string, required: true, description: Global API Key"
    echo "field: zone_id, type: string, required: true, description: Zone ID for domain"
    echo "field: domain, type: string, required: true, description: Domain to update"
    echo "field: host, type: string, required: false, default: @, description: Host record"
}

provider_validate() {
    if [ -z "${CLOUDFLARE_EMAIL}" ] || [ -z "${CLOUDFLARE_API_KEY}" ] || [ -z "${CLOUDFLARE_ZONE_ID}" ]; then
        echo "Error: Cloudflare credentials not configured"
        return 1
    fi
    return 0
}

provider_update() {
    local domain="$1"
    local host="${2:-@}"
    local ip="$3"
    local email="${CLOUDFLARE_EMAIL}"
    local api_key="${CLOUDFLARE_API_KEY}"
    local zone_id="${CLOUDFLARE_ZONE_ID}"
    
    # Build record name
    local record_name="$host.$domain"
    [ "$host" = "@" ] && record_name="$domain"
    
    # Get existing record ID
    local api_url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records"
    local records=$(curl -s -X GET "$api_url?type=A&name=$record_name" \
        -H "X-Auth-Email: $email" \
        -H "X-Auth-Key: $api_key" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    local record_id=$(echo "$records" | grep -oE '"id":"[^"]*"' | head -n1 | cut -d'"' -f4)
    
    local response
    if [ -n "$record_id" ]; then
        # Update existing record
        response=$(curl -s -w "\n%{http_code}" -X PUT \
            "$api_url/$record_id" \
            -H "X-Auth-Email: $email" \
            -H "X-Auth-Key: $api_key" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}" \
            2>/dev/null)
    else
        # Create new record
        response=$(curl -s -w "\n%{http_code}" -X POST \
            "$api_url" \
            -H "X-Auth-Email: $email" \
            -H "X-Auth-Key: $api_key" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}" \
            2>/dev/null)
    fi
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "[Cloudflare] Successfully updated $record_name to $ip"
        return 0
    else
        echo "[Cloudflare] Failed to update DNS (HTTP $http_code)"
        return 1
    fi
}

provider_test() {
    local email="${CLOUDFLARE_EMAIL}"
    local api_key="${CLOUDFLARE_API_KEY}"
    
    if [ -z "$email" ] || [ -z "$api_key" ]; then
        echo "Error: Credentials not configured"
        return 1
    fi
    
    # Test API connectivity
    local response=$(curl -s -w "\n%{http_code}" \
        "https://api.cloudflare.com/client/v4/user" \
        -H "X-Auth-Email: $email" \
        -H "X-Auth-Key: $api_key" \
        2>/dev/null | tail -n1)
    
    if [ "$response" = "200" ]; then
        echo "[Cloudflare] API connection successful"
        return 0
    else
        echo "[Cloudflare] API connection failed (HTTP $response)"
        return 1
    fi
}