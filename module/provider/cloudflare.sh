#!/bin/sh
# Cloudflare DNS provider for Access Eternal

CLOUDFLARE_API="https://api.cloudflare.com/client/v4"

provider_validate() {
    [ -z "$CLOUDFLARE_API_TOKEN" ] && { printf "WARNING: No CLOUDFLARE_API_TOKEN configured\n"; return 6; }
    [ -z "$CLOUDFLARE_ZONE_ID" ] && { printf "WARNING: No CLOUDFLARE_ZONE_ID configured\n"; return 6; }
    return 0
}

_cf_record_name() {
    if [ -z "$HOST" ] || [ "$HOST" = "@" ]; then
        printf "%s" "$DOMAIN"
    else
        printf "%s.%s" "$HOST" "$DOMAIN"
    fi
}

# Extract the first "id":"..." value from a Cloudflare JSON response on stdin
_cf_extract_id() {
    sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1
}

# $1 = record type (A/AAAA) -> prints existing record id, empty if none
_cf_find_record_id() {
    curl -s --fail -X GET "$CLOUDFLARE_API/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=$1&name=$(_cf_record_name)" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        | _cf_extract_id
}

# $1 = record type (A/AAAA), $2 = IP value
provider_update_record() {
    _cf_type="$1"
    _cf_value="$2"
    _cf_id=$(_cf_find_record_id "$_cf_type")

    if [ -n "$_cf_id" ]; then
        curl -s --fail -X PATCH "$CLOUDFLARE_API/zones/$CLOUDFLARE_ZONE_ID/dns_records/$_cf_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"$_cf_value\"}" >/dev/null
    else
        curl -s --fail -X POST "$CLOUDFLARE_API/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"$_cf_type\",\"name\":\"$(_cf_record_name)\",\"content\":\"$_cf_value\",\"ttl\":600,\"proxied\":false}" >/dev/null
    fi
}
