#!/bin/sh
# Google Cloud DNS Provider - Pure Shell Implementation
# No gcloud CLI dependency - uses direct REST API with OAuth2

provider_info() {
    echo "name: Google Cloud"
    echo "version: 2.0.0"
    echo "author: Access Team"
    echo "type: dns"
    echo "description: Google Cloud DNS (Pure Shell)"
}

provider_config() {
    echo "field: project_id, type: string, required: true, description: GCP Project ID"
    echo "field: zone_name, type: string, required: true, description: Cloud DNS Zone name"
    echo "field: client_email, type: string, required: true, description: Service Account email"
    echo "field: private_key, type: string, required: true, description: Service Account private key (base64)"
    echo "field: domain, type: string, required: true, description: Domain to update"
    echo "field: host, type: string, required: false, default: @, description: Host record"
}

provider_validate() {
    if [ -z "${GCLOUD_PROJECT_ID}" ] || [ -z "${GCLOUD_ZONE_NAME}" ] || [ -z "${GCLOUD_CLIENT_EMAIL}" ] || [ -z "${GCLOUD_PRIVATE_KEY}" ]; then
        echo "Error: Google Cloud credentials not configured"
        return 1
    fi
    
    # Check for required tools
    if ! command -v openssl >/dev/null 2>&1; then
        echo "Error: openssl is required for JWT signing"
        return 1
    fi
    
    return 0
}

# Create JWT for Google OAuth2
create_jwt() {
    local client_email="$1"
    local private_key_base64="$2"
    local scope="https://www.googleapis.com/auth/ndev.clouddns.readwrite"
    
    # JWT header
    local header='{"alg":"RS256","typ":"JWT"}'
    local header_base64=$(echo -n "$header" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
    
    # JWT claims
    local iat=$(date +%s)
    local exp=$(expr $iat + 3600)
    local claims="{\"iss\":\"$client_email\",\"scope\":\"$scope\",\"aud\":\"https://oauth2.googleapis.com/token\",\"iat\":$iat,\"exp\":$exp}"
    local claims_base64=$(echo -n "$claims" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
    
    # Decode private key
    local key_file=$(mktemp /tmp/gcloud_key.XXXXXX 2>/dev/null || echo "/tmp/gcloud_key_$$")
    echo "$private_key_base64" | base64 -d > "$key_file" 2>/dev/null
    
    # Sign JWT
    local signature=$(echo -n "${header_base64}.${claims_base64}" | \
        openssl dgst -sha256 -sign "$key_file" | \
        openssl base64 -A | tr '+/' '-_' | tr -d '=')
    
    rm -f "$key_file" 2>/dev/null
    
    echo "${header_base64}.${claims_base64}.${signature}"
}

# Get OAuth2 access token
get_access_token() {
    local jwt="$1"
    
    local response=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt" 2>/dev/null)
    
    # Extract access token
    echo "$response" | grep -oE '"access_token":"[^"]*"' | cut -d'"' -f4
}

provider_update() {
    local domain="$1"
    local host="${2:-@}"
    local ip="$3"
    local record_type="${4:-}"  # Optional 4th parameter
    local project_id="${GCLOUD_PROJECT_ID}"
    local zone_name="${GCLOUD_ZONE_NAME}"
    local client_email="${GCLOUD_CLIENT_EMAIL}"
    local private_key="${GCLOUD_PRIVATE_KEY}"
    
    # Auto-detect record type if not provided
    if [ -z "$record_type" ]; then
        if echo "$ip" | grep -q ':'; then
            record_type="AAAA"
        else
            record_type="A"
        fi
    fi
    
    echo "[Google Cloud] Updating $record_type record for $host.$domain with IP: $ip"
    
    # Get access token
    local jwt=$(create_jwt "$client_email" "$private_key")
    local access_token=$(get_access_token "$jwt")
    
    if [ -z "$access_token" ]; then
        echo "[Google Cloud] Failed to obtain access token"
        return 1
    fi
    
    # Build record name
    local record_name="$host.$domain."
    [ "$host" = "@" ] && record_name="$domain."
    
    # Get current record set
    local api_url="https://dns.googleapis.com/dns/v1/projects/$project_id/managedZones/$zone_name/rrsets"
    local current_rrset=$(curl -s -X GET "$api_url?name=$record_name&type=A" \
        -H "Authorization: Bearer $access_token" 2>/dev/null)
    
    # Create change request
    local change_body="{
        \"additions\": [{
            \"name\": \"$record_name\",
            \"type\": \"A\",
            \"ttl\": 300,
            \"rrdatas\": [\"$ip\"]
        }]"
    
    # Add deletion if record exists
    if echo "$current_rrset" | grep -q "\"name\""; then
        local old_ip=$(echo "$current_rrset" | grep -oE '"rrdatas":\["[^"]*"\]' | cut -d'"' -f4)
        if [ "$old_ip" = "$ip" ]; then
            echo "[Google Cloud] IP unchanged: $ip"
            return 0
        fi
        
        change_body="$change_body,
        \"deletions\": [{
            \"name\": \"$record_name\",
            \"type\": \"A\",
            \"ttl\": 300,
            \"rrdatas\": [\"$old_ip\"]
        }]"
    fi
    
    change_body="$change_body}"
    
    # Apply change
    local change_url="https://dns.googleapis.com/dns/v1/projects/$project_id/managedZones/$zone_name/changes"
    local response=$(curl -s -w "\n%{http_code}" -X POST "$change_url" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$change_body" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "[Google Cloud] Successfully updated $record_name to $ip"
        return 0
    else
        echo "[Google Cloud] Failed to update DNS (HTTP $http_code)"
        return 1
    fi
}

provider_test() {
    local project_id="${GCLOUD_PROJECT_ID}"
    local zone_name="${GCLOUD_ZONE_NAME}"
    local client_email="${GCLOUD_CLIENT_EMAIL}"
    local private_key="${GCLOUD_PRIVATE_KEY}"
    
    if [ -z "$project_id" ] || [ -z "$zone_name" ]; then
        echo "Error: Project ID or Zone name not configured"
        return 1
    fi
    
    # Test authentication
    local jwt=$(create_jwt "$client_email" "$private_key")
    local access_token=$(get_access_token "$jwt")
    
    if [ -z "$access_token" ]; then
        echo "[Google Cloud] Authentication failed"
        return 1
    fi
    
    # Test zone access
    local api_url="https://dns.googleapis.com/dns/v1/projects/$project_id/managedZones/$zone_name"
    local response=$(curl -s -w "\n%{http_code}" -X GET "$api_url" \
        -H "Authorization: Bearer $access_token" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "[Google Cloud] Authentication successful, zone accessible"
        return 0
    else
        echo "[Google Cloud] Cannot access zone (HTTP $http_code)"
        return 1
    fi
}