#!/bin/sh
# GoDaddy DNS provider for Access Eternal

provider_validate() {
    [ -z "$GODADDY_KEY" ] && { printf "WARNING: No GODADDY_KEY configured\n"; return 6; }
    [ -z "$GODADDY_SECRET" ] && { printf "WARNING: No GODADDY_SECRET configured\n"; return 6; }
    return 0
}

# $1 = record type (A/AAAA), $2 = IP value
provider_update_record() {
    curl -s --fail -X PUT "https://api.godaddy.com/v1/domains/$DOMAIN/records/$1/$HOST" \
        -H "Authorization: sso-key $GODADDY_KEY:$GODADDY_SECRET" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"$2\",\"ttl\":600}]" >/dev/null
}
