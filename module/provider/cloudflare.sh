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

# Extract the first "id":"..." value from a Cloudflare JSON response on stdin.
# Cloudflare objects nest other "id" fields (account.id, plan.id, ...) after the
# resource's own id, so a greedy sed match would grab the wrong one; grep -o
# lists matches in appearance order, so head -1 gets the resource's own id.
_cf_extract_id() {
    grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"\([^"]*\)"/\1/'
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

# Install-time: prompt for this provider's credentials and resolve anything
# that depends on the domain (Zone ID). $1 = domain, $2 = host (unused here)
provider_install_prompt() {
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        printf "Enter your Cloudflare API Token (needs Zone:Read + DNS:Edit permissions): "
        if [ -c /dev/tty ]; then read -r CLOUDFLARE_API_TOKEN < /dev/tty; else read -r CLOUDFLARE_API_TOKEN; fi
    fi

    if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
        printf "Resolving Cloudflare Zone ID for %s...\n" "$1"
        _cf_zone_resp=$(curl -s -X GET "$CLOUDFLARE_API/zones?name=$1" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json")
        CLOUDFLARE_ZONE_ID=$(printf "%s" "$_cf_zone_resp" | _cf_extract_id)
        if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
            printf "WARNING: Could not auto-resolve Zone ID (check token permissions and domain).\n"
            printf "Enter your Cloudflare Zone ID manually (Cloudflare dashboard > your domain > Overview > API section): "
            if [ -c /dev/tty ]; then read -r CLOUDFLARE_ZONE_ID < /dev/tty; else read -r CLOUDFLARE_ZONE_ID; fi
        else
            printf "Resolved Zone ID: %s\n" "$CLOUDFLARE_ZONE_ID"
        fi
    fi
}

# Install-time: print the values that will be saved, for install.sh's confirmation prompt
provider_install_summary() {
    printf "Cloudflare API Token: %s\n" "$CLOUDFLARE_API_TOKEN"
    printf "Cloudflare Zone ID: %s\n" "$CLOUDFLARE_ZONE_ID"
}

# Install-time: append this provider's fields to the config file at $1
provider_write_config() {
    printf "CLOUDFLARE_API_TOKEN=%s\n" "$CLOUDFLARE_API_TOKEN" >> "$1"
    printf "CLOUDFLARE_ZONE_ID=%s\n" "$CLOUDFLARE_ZONE_ID" >> "$1"
}
