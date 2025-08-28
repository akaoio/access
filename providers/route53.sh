#!/bin/sh
# AWS Route53 DNS Provider - Pure Shell Implementation
# No AWS CLI dependency - uses direct REST API with Signature V4

provider_info() {
    echo "name: AWS Route53"
    echo "version: 2.0.0"
    echo "author: Access Team"
    echo "type: dns"
    echo "description: AWS Route53 DNS (Pure Shell)"
}

provider_config() {
    echo "field: zone_id, type: string, required: true, description: Route53 Hosted Zone ID"
    echo "field: access_key, type: string, required: true, description: AWS Access Key ID"
    echo "field: secret_key, type: string, required: true, description: AWS Secret Access Key"
    echo "field: region, type: string, required: false, default: us-east-1, description: AWS Region"
    echo "field: domain, type: string, required: true, description: Domain to update"
    echo "field: host, type: string, required: false, default: @, description: Host record"
}

provider_validate() {
    if [ -z "${ROUTE53_ZONE_ID}" ] || [ -z "${ROUTE53_ACCESS_KEY}" ] || [ -z "${ROUTE53_SECRET_KEY}" ]; then
        echo "Error: AWS credentials not configured"
        return 1
    fi
    
    # Check for required tools
    if ! command -v openssl >/dev/null 2>&1; then
        echo "Error: openssl is required for AWS signature"
        return 1
    fi
    
    return 0
}

# AWS Signature V4 implementation in pure shell
aws_sign_v4() {
    local method="$1"
    local uri="$2"
    local query="$3"
    local payload="$4"
    local service="route53"
    local region="${ROUTE53_REGION:-us-east-1}"
    local access_key="${ROUTE53_ACCESS_KEY}"
    local secret_key="${ROUTE53_SECRET_KEY}"
    
    # Get current date/time
    local timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
    local datestamp=$(date -u '+%Y%m%d')
    
    # Create canonical request
    local payload_hash=$(echo -n "$payload" | openssl dgst -sha256 | cut -d' ' -f2)
    local canonical_headers="host:route53.amazonaws.com\nx-amz-date:$timestamp"
    local signed_headers="host;x-amz-date"
    
    local canonical_request="$method
$uri
$query
$canonical_headers

$signed_headers
$payload_hash"
    
    # Create string to sign
    local algorithm="AWS4-HMAC-SHA256"
    local credential_scope="$datestamp/$region/$service/aws4_request"
    local canonical_hash=$(echo -n "$canonical_request" | openssl dgst -sha256 | cut -d' ' -f2)
    
    local string_to_sign="$algorithm
$timestamp
$credential_scope
$canonical_hash"
    
    # Calculate signature
    local kDate=$(echo -n "$datestamp" | openssl dgst -sha256 -hmac "AWS4$secret_key" -binary)
    local kRegion=$(echo -n "$region" | openssl dgst -sha256 -mac HMAC -macopt key:"$kDate" -binary)
    local kService=$(echo -n "$service" | openssl dgst -sha256 -mac HMAC -macopt key:"$kRegion" -binary)
    local kSigning=$(echo -n "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt key:"$kService" -binary)
    local signature=$(echo -n "$string_to_sign" | openssl dgst -sha256 -mac HMAC -macopt key:"$kSigning" | cut -d' ' -f2)
    
    # Create authorization header
    echo "Authorization: $algorithm Credential=$access_key/$credential_scope, SignedHeaders=$signed_headers, Signature=$signature"
    echo "x-amz-date: $timestamp"
}

provider_update() {
    local domain="$1"
    local host="${2:-@}"
    local ip="$3"
    local record_type="${4:-}"  # Optional 4th parameter
    local zone_id="${ROUTE53_ZONE_ID}"
    
    # Auto-detect record type if not provided
    if [ -z "$record_type" ]; then
        if echo "$ip" | grep -q ':'; then
            record_type="AAAA"
        else
            record_type="A"
        fi
    fi
    
    echo "[Route53] Updating $record_type record for $host.$domain with IP: $ip"
    
    # Build record name
    local record_name="$host.$domain."
    [ "$host" = "@" ] && record_name="$domain."
    
    # Create change batch XML (Route53 uses XML not JSON)
    local change_batch="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\">
    <ChangeBatch>
        <Changes>
            <Change>
                <Action>UPSERT</Action>
                <ResourceRecordSet>
                    <Name>$record_name</Name>
                    <Type>A</Type>
                    <TTL>300</TTL>
                    <ResourceRecords>
                        <ResourceRecord>
                            <Value>$ip</Value>
                        </ResourceRecord>
                    </ResourceRecords>
                </ResourceRecordSet>
            </Change>
        </Changes>
    </ChangeBatch>
</ChangeResourceRecordSetsRequest>"
    
    # Sign request
    local uri="/2013-04-01/hostedzone/$zone_id/rrset"
    local auth_headers=$(aws_sign_v4 "POST" "$uri" "" "$change_batch")
    
    # Make API call
    local response=$(curl -s -w "\n%{http_code}" -X POST "https://route53.amazonaws.com$uri" \
        -H "Content-Type: application/xml" \
        -H "$(echo "$auth_headers" | head -1)" \
        -H "$(echo "$auth_headers" | tail -1)" \
        -d "$change_batch" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "[Route53] Successfully updated $record_name to $ip"
        return 0
    else
        echo "[Route53] Failed to update DNS (HTTP $http_code)"
        echo "[Route53] Response: $(echo "$response" | head -n-1)"
        return 1
    fi
}

provider_test() {
    local zone_id="${ROUTE53_ZONE_ID}"
    
    if [ -z "$zone_id" ]; then
        echo "Error: Zone ID not configured"
        return 1
    fi
    
    # Test with a simple GET request
    local uri="/2013-04-01/hostedzone/$zone_id"
    local auth_headers=$(aws_sign_v4 "GET" "$uri" "" "")
    
    local response=$(curl -s -w "\n%{http_code}" -X GET "https://route53.amazonaws.com$uri" \
        -H "$(echo "$auth_headers" | head -1)" \
        -H "$(echo "$auth_headers" | tail -1)" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        echo "[Route53] Authentication successful, zone accessible"
        return 0
    else
        echo "[Route53] Authentication failed (HTTP $http_code)"
        return 1
    fi
}