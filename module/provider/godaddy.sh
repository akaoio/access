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

# Install-time: prompt for this provider's credentials.
# $1 = domain, $2 = host (unused by GoDaddy, kept for a uniform hook signature)
provider_install_prompt() {
    if [ -z "$GODADDY_KEY" ]; then
        printf "Enter your GoDaddy API Key: "
        if [ -c /dev/tty ]; then read -r GODADDY_KEY < /dev/tty; else read -r GODADDY_KEY; fi
    fi

    if [ -z "$GODADDY_SECRET" ]; then
        printf "Enter your GoDaddy API Secret: "
        if [ -c /dev/tty ]; then read -r GODADDY_SECRET < /dev/tty; else read -r GODADDY_SECRET; fi
    fi
}

# Install-time: print the values that will be saved, for install.sh's confirmation prompt
provider_install_summary() {
    printf "GoDaddy API Key: %s\n" "$GODADDY_KEY"
    printf "GoDaddy API Secret: %s\n" "$GODADDY_SECRET"
}

# Install-time: append this provider's fields to the config file at $1
provider_write_config() {
    printf "GODADDY_KEY=%s\n" "$GODADDY_KEY" >> "$1"
    printf "GODADDY_SECRET=%s\n" "$GODADDY_SECRET" >> "$1"
}
