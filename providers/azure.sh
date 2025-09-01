#!/bin/sh
# Azure DNS Provider
# API Documentation: https://docs.microsoft.com/en-us/rest/api/dns/

provider_info() {
    echo "name: Azure"
    echo "version: 1.0.0"
    echo "author: Access Team"
    echo "type: dns"
    echo "description: Microsoft Azure DNS Service"
}

provider_config() {
    echo "field: subscription_id, type: string, required: true, description: Azure Subscription ID"
    echo "field: resource_group, type: string, required: true, description: Resource Group Name"
    echo "field: tenant_id, type: string, required: true, description: Azure Tenant ID"
    echo "field: client_id, type: string, required: true, description: Service Principal Client ID"
    echo "field: client_secret, type: string, required: true, description: Service Principal Client Secret"
    echo "field: domain, type: string, required: true, description: DNS Zone name"
    echo "field: host, type: string, required: false, default: @, description: Host record"
}

provider_validate() {
    if [ -z "${AZURE_SUBSCRIPTION_ID}" ] || [ -z "${AZURE_RESOURCE_GROUP}" ] || \
       [ -z "${AZURE_TENANT_ID}" ] || [ -z "${AZURE_CLIENT_ID}" ] || [ -z "${AZURE_CLIENT_SECRET}" ]; then
        echo "Error: Azure credentials not configured"
        return 1
    fi
    return 0
}

provider_update() {
    local domain="$1"
    local host="${2:-@}"
    local ip="$3"
    local record_type="${4:-}"  # Optional 4th parameter
    local subscription_id="${AZURE_SUBSCRIPTION_ID}"
    local resource_group="${AZURE_RESOURCE_GROUP}"
    local tenant_id="${AZURE_TENANT_ID}"
    local client_id="${AZURE_CLIENT_ID}"
    local client_secret="${AZURE_CLIENT_SECRET}"
    
    # Auto-detect record type if not provided
    if [ -z "$record_type" ]; then
        if echo "$ip" | grep -q ':'; then
            record_type="AAAA"
        else
            record_type="A"
        fi
    fi
    
    echo "[Azure] Updating $record_type record for $host.$domain with IP: $ip"
    
    # Get access token (secure handling of client secret)
    local temp_data=$(mktemp -t "azure_auth.XXXXXX" 2>/dev/null || echo "/tmp/azure_auth.$$.$RANDOM")
    echo "grant_type=client_credentials&client_id=$client_id&client_secret=$client_secret&scope=https://management.azure.com/.default" > "$temp_data"
    chmod 600 "$temp_data"  # Restrict access to owner only
    
    local token_response=$(curl -s -X POST \
        "https://login.microsoftonline.com/$tenant_id/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "@$temp_data" 2>/dev/null)
    
    # Securely cleanup temporary file
    rm -f "$temp_data"
    
    local access_token=$(echo "$token_response" | grep -oE '"access_token":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$access_token" ]; then
        echo "[Azure] Failed to obtain access token"
        return 1
    fi
    
    # Prepare record name
    local record_name="$host"
    [ "$host" = "@" ] && record_name="@"
    
    # API URL for DNS record
    local api_url="https://management.azure.com/subscriptions/$subscription_id"
    api_url="$api_url/resourceGroups/$resource_group"
    api_url="$api_url/providers/Microsoft.Network/dnsZones/$domain"
    api_url="$api_url/A/$record_name?api-version=2018-05-01"
    
    # Update DNS record
    local response=$(curl -s -w "\n%{http_code}" -X PUT "$api_url" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "{
            \"properties\": {
                \"TTL\": 300,
                \"ARecords\": [
                    {
                        \"ipv4Address\": \"$ip\"
                    }
                ]
            }
        }" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "[Azure] Successfully updated $record_name.$domain to $ip"
        return 0
    else
        echo "[Azure] Failed to update DNS (HTTP $http_code)"
        return 1
    fi
}

provider_test() {
    local subscription_id="${AZURE_SUBSCRIPTION_ID}"
    local tenant_id="${AZURE_TENANT_ID}"
    local client_id="${AZURE_CLIENT_ID}"
    local client_secret="${AZURE_CLIENT_SECRET}"
    
    if [ -z "$subscription_id" ] || [ -z "$tenant_id" ] || [ -z "$client_id" ] || [ -z "$client_secret" ]; then
        echo "Error: Credentials not configured"
        return 1
    fi
    
    # Test authentication (secure handling of client secret)
    local temp_data=$(mktemp -t "azure_test.XXXXXX" 2>/dev/null || echo "/tmp/azure_test.$$.$RANDOM")
    echo "grant_type=client_credentials&client_id=$client_id&client_secret=$client_secret&scope=https://management.azure.com/.default" > "$temp_data"
    chmod 600 "$temp_data"  # Restrict access to owner only
    
    local token_response=$(curl -s -X POST \
        "https://login.microsoftonline.com/$tenant_id/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "@$temp_data" 2>/dev/null)
    
    # Securely cleanup temporary file
    rm -f "$temp_data"
    
    if echo "$token_response" | grep -q "access_token"; then
        echo "[Azure] Authentication successful"
        return 0
    else
        echo "[Azure] Authentication failed"
        return 1
    fi
}