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
    local subscription_id="${AZURE_SUBSCRIPTION_ID}"
    local resource_group="${AZURE_RESOURCE_GROUP}"
    local tenant_id="${AZURE_TENANT_ID}"
    local client_id="${AZURE_CLIENT_ID}"
    local client_secret="${AZURE_CLIENT_SECRET}"
    
    # Get access token
    local token_response=$(curl -s -X POST \
        "https://login.microsoftonline.com/$tenant_id/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d "scope=https://management.azure.com/.default" 2>/dev/null)
    
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
    
    # Test authentication
    local token_response=$(curl -s -X POST \
        "https://login.microsoftonline.com/$tenant_id/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d "scope=https://management.azure.com/.default" 2>/dev/null)
    
    if echo "$token_response" | grep -q "access_token"; then
        echo "[Azure] Authentication successful"
        return 0
    else
        echo "[Azure] Authentication failed"
        return 1
    fi
}