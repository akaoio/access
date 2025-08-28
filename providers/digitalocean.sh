#!/bin/sh
# DigitalOcean DNS Provider
# API Documentation: https://docs.digitalocean.com/reference/api/

provider_info() {
    echo "name: DigitalOcean"
    echo "version: 1.0.0"
    echo "author: Access Team"
    echo "type: dns"
    echo "description: DigitalOcean API v2"
}

provider_config() {
    echo "field: token, type: string, required: true, description: Personal Access Token"
    echo "field: domain, type: string, required: true, description: Domain to update"
    echo "field: host, type: string, required: false, default: @, description: Host record"
}

provider_validate() {
    if [ -z "${DIGITALOCEAN_TOKEN}" ]; then
        echo "Error: DigitalOcean API token not configured"
        return 1
    fi
    return 0
}

provider_update() {
    local domain="$1"
    local host="${2:-@}"
    local ip="$3"
    local record_type="${4:-}"  # Optional 4th parameter
    local token="${DIGITALOCEAN_TOKEN}"
    
    # Auto-detect record type if not provided
    if [ -z "$record_type" ]; then
        if echo "$ip" | grep -q ':'; then
            record_type="AAAA"
        else
            record_type="A"
        fi
    fi
    
    echo "[DigitalOcean] Updating $record_type record for $host.$domain with IP: $ip"
    
    # API endpoint
    local api_url="https://api.digitalocean.com/v2/domains/$domain/records"
    
    # Get existing records
    local records=$(curl -s -X GET "$api_url?type=$record_type&name=$host" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    local record_id=$(echo "$records" | grep -oE '"id":[0-9]+' | head -n1 | cut -d: -f2)
    
    local response
    if [ -n "$record_id" ]; then
        # Update existing record
        response=$(curl -s -w "\n%{http_code}" -X PUT \
            "$api_url/$record_id" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "{\"data\":\"$ip\"}" \
            2>/dev/null)
    else
        # Create new record
        response=$(curl -s -w "\n%{http_code}" -X POST \
            "$api_url" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"$host\",\"data\":\"$ip\",\"ttl\":600}" \
            2>/dev/null)
    fi
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "[DigitalOcean] Successfully updated $host.$domain to $ip"
        return 0
    else
        echo "[DigitalOcean] Failed to update DNS (HTTP $http_code)"
        return 1
    fi
}

provider_test() {
    local token="${DIGITALOCEAN_TOKEN}"
    
    if [ -z "$token" ]; then
        echo "Error: Token not configured"
        return 1
    fi
    
    # Test API connectivity
    local response=$(curl -s -w "\n%{http_code}" \
        "https://api.digitalocean.com/v2/account" \
        -H "Authorization: Bearer $token" \
        2>/dev/null | tail -n1)
    
    if [ "$response" = "200" ]; then
        echo "[DigitalOcean] API connection successful"
        return 0
    else
        echo "[DigitalOcean] API connection failed (HTTP $response)"
        return 1
    fi
}