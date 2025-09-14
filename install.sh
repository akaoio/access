#!/bin/sh
exec < /dev/tty # Do not remove this line

godaddy_key=""
godaddy_secret=""
domain=""
host=""

# Transform long options to short ones
for arg in "$@"; do
    shift # Shift all arguments to the left
    case "$arg" in
        --godaddy_key)    set -- "$@" "-k" ;;
        --godaddy_secret) set -- "$@" "-s" ;;
        --domain)         set -- "$@" "-d" ;;
        --host)           set -- "$@" "-h" ;;
        *)                set -- "$@" "$arg" ;;
    esac
done

# Check options
while getopts "k:s:d:h:" opt; do
    case $opt in
        k) godaddy_key="$OPTARG" ;;
        s) godaddy_secret="$OPTARG" ;;
        d) domain="$OPTARG" ;;
        h) host="$OPTARG" ;;
        *) printf "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Set LIB if it doesn't exist
if [ -z "$LIB" ]; then
    LIB="/usr/local/lib/access"
fi

# Install git if not exists
if ! command -v git >/dev/null 2>&1; then
    apt update && apt install -y git
fi

# Clone access repo to $LIB directory
if [ ! -d "$LIB" ]; then
    git clone -b main https://github.com/akaoio/access "$LIB"
fi

# Initialize essential variables and functions
if [ -f "$LIB/init.sh" ]; then
    . "$LIB/init.sh"
fi

# Check if Access is installed
# If Access is already installed, ask if the user wants to reinstall it
if [ "$INSTALLED" = true ]; then
    prompt_input "Access is already installed! Do you want to reinstall it? [y/N]" "yes_no" "$ABORTED" || exit 1
fi

# Prompt for missing values
if [ -z "$godaddy_key" ]; then
    prompt_input "Enter your GoDaddy API Key" "non_empty"
    godaddy_key="$PROMPT_RESULT"
fi

if [ -z "$godaddy_secret" ]; then
    prompt_input "Enter your GoDaddy API Secret" "non_empty"
    godaddy_secret="$PROMPT_RESULT"
fi

if [ -z "$domain" ]; then
    prompt_input "Enter your domain name" "non_empty"
    domain="$PROMPT_RESULT"
fi

if [ -z "$host" ]; then
    prompt_input "Enter your host name" "non_empty"
    host="$PROMPT_RESULT"
fi
# Confirm values
printf "Please confirm the following values:\n"
printf "GoDaddy API Key: %s\n" "$godaddy_key"
printf "GoDaddy API Secret: %s\n" "$godaddy_secret"
printf "Domain: %s\n" "$domain"
printf "Host: %s\n" "$host"
prompt_input "Continue with these values? [y/N]" "yes_no" "$ABORTED" || exit 1

# Backup current config file if exists
if [ -f "$CONFIG" ]; then
    mv "$CONFIG" "$CONFIG.$(date +%s).bak"
fi

# Create config directory and generate config from template
mkdir -p "$(dirname "$CONFIG")"
sed "s/__GODADDY_KEY__/$godaddy_key/g; s/__GODADDY_SECRET__/$godaddy_secret/g; s/__DOMAIN__/$domain/g; s/__HOST__/$host/g" "$LIB/config.env.template" > "$CONFIG"

# Copy entry executable file, this makes Access available globally
cp "$LIB/access" "$BIN"