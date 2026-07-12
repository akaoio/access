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

# Extract every top-level "id":"..." from a dns_records LIST response, one per
# line. Unlike _cf_extract_id's single-object case, each array item here is a
# flat record object with no nested ids, so every match is a real record id -
# including any leftover duplicates from a previous failed sync.
_cf_extract_ids() {
    grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/'
}

# $1 = record type (A/AAAA) -> prints one existing record id per line (there
# should only ever be one, but a network hiccup mid-sync can leave duplicates
# behind - callers must not just take the first and ignore the rest).
# Returns nonzero with no output if the API call itself failed, distinct from
# "API call succeeded, zero matching records" (empty output, success).
_cf_find_record_id() {
    _cf_lookup_resp=$(curl -s --fail -X GET "$CLOUDFLARE_API/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=$1&name=$(_cf_record_name)" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json") || return 1
    case "$_cf_lookup_resp" in
        *'"success":true'*) printf "%s" "$_cf_lookup_resp" | _cf_extract_ids; return 0 ;;
        *) return 1 ;;
    esac
}

# $1 = record type (A/AAAA), $2 = IP value
provider_update_record() {
    _cf_type="$1"
    _cf_value="$2"

    # A failed lookup must abort, not fall through to creating a new record -
    # that fallthrough is exactly what left akao.io/pi with duplicate stale
    # A/AAAA records after a lookup failed during a router IP-rotation blip.
    _cf_ids=$(_cf_find_record_id "$_cf_type") || {
        printf "ERROR: Failed to look up existing %s record\n" "$_cf_type"
        return 1
    }
    _cf_id=$(printf "%s\n" "$_cf_ids" | head -1)
    _cf_dup_ids=$(printf "%s\n" "$_cf_ids" | tail -n +2)

    if [ -n "$_cf_id" ]; then
        _cf_write_resp=$(curl -s --fail -X PATCH "$CLOUDFLARE_API/zones/$CLOUDFLARE_ZONE_ID/dns_records/$_cf_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"$_cf_value\"}") || { printf "ERROR: PATCH request failed for %s\n" "$_cf_type"; return 1; }
    else
        _cf_write_resp=$(curl -s --fail -X POST "$CLOUDFLARE_API/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"$_cf_type\",\"name\":\"$(_cf_record_name)\",\"content\":\"$_cf_value\",\"ttl\":600,\"proxied\":false}") || { printf "ERROR: POST request failed for %s\n" "$_cf_type"; return 1; }
    fi

    # Cloudflare can return HTTP 200 with a body-level rejection (validation
    # errors, some rate-limit cases); curl --fail only sees HTTP status, so
    # the "success" field must be checked explicitly too.
    case "$_cf_write_resp" in
        *'"success":true'*) ;;
        *) printf "ERROR: Cloudflare rejected %s update: %s\n" "$_cf_type" "$_cf_write_resp"; return 1 ;;
    esac

    # Self-heal: delete any leftover duplicate records for this name+type so
    # a resolver can never be handed a stale duplicate again.
    if [ -n "$_cf_dup_ids" ]; then
        printf "%s\n" "$_cf_dup_ids" | while IFS= read -r _cf_dup_id; do
            [ -n "$_cf_dup_id" ] && curl -s --fail -X DELETE "$CLOUDFLARE_API/zones/$CLOUDFLARE_ZONE_ID/dns_records/$_cf_dup_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" >/dev/null
        done
    fi

    return 0
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
