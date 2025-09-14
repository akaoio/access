#!/bin/sh

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

# Clone/update access repo to $LIB directory - force fresh clone
rm -rf "$LIB"
git clone -b main https://github.com/akaoio/access "$LIB"

# Initialize essential variables and functions
if [ -f "$LIB/init.sh" ]; then
    . "$LIB/init.sh"
fi

# Check if Access is installed
# If Access is already installed, ask if the user wants to reinstall it
if [ "$INSTALLED" = true ]; then
    printf "Access is already installed! Do you want to reinstall it? [y/N]: "
    read -r confirm < /dev/tty
    case "$confirm" in
        [Yy]*) ;;
        *) printf "Installation aborted.\n"; exit 1 ;;
    esac
fi

# Prompt for missing values
if [ -z "$godaddy_key" ]; then
    printf "Enter your GoDaddy API Key: "
    read -r godaddy_key < /dev/tty
fi

if [ -z "$godaddy_secret" ]; then
    printf "Enter your GoDaddy API Secret: "
    read -r godaddy_secret < /dev/tty
fi

if [ -z "$domain" ]; then
    printf "Enter your domain name: "
    read -r domain < /dev/tty
fi

if [ -z "$host" ]; then
    printf "Enter your host name: "
    read -r host < /dev/tty
fi

# Confirm values
printf "Please confirm the following values:\n"
printf "GoDaddy API Key: %s\n" "$godaddy_key"
printf "GoDaddy API Secret: %s\n" "$godaddy_secret"
printf "Domain: %s\n" "$domain"
printf "Host: %s\n" "$host"
printf "Continue with these values? [y/N]: "
read -r confirm < /dev/tty
case "$confirm" in
    [Yy]*) ;;
    *) printf "Installation aborted.\n"; exit 1 ;;
esac

# Backup current config file if exists
if [ -f "$CONFIG" ]; then
    mv "$CONFIG" "$CONFIG.$(date +%s).bak"
fi

# Create config directory and generate config from template
printf "Creating config directory...\n"
mkdir -p "$(dirname "$CONFIG")"
printf "Processing config template...\n"
sed "s/__GODADDY_KEY__/$godaddy_key/g; s/__GODADDY_SECRET__/$godaddy_secret/g; s/__DOMAIN__/$domain/g; s/__HOST__/$host/g" "$LIB/config.env.template" > "$CONFIG"
printf "Config file created at %s\n" "$CONFIG"

# Copy entry executable file, this makes Access available globally
printf "Copying executable...\n"
cp "$LIB/access" "$BIN"
chmod +x "$BIN"
printf "Executable copied successfully\n"

# Create log directories
printf "Creating log directories...\n"
mkdir -p /var/log/access
chmod 755 /var/log/access
printf "Log directories created\n"

# Process and install systemd service files
printf "Installing systemd services...\n"
sed "s|__BIN__|$BIN|g; s|__LIB__|$LIB|g" "$LIB/access.service.template" > /etc/systemd/system/access.service
sed "s|__BIN__|$BIN|g; s|__LIB__|$LIB|g" "$LIB/access-sync.service.template" > /etc/systemd/system/access-sync.service
sed "s|__BIN__|$BIN|g; s|__LIB__|$LIB|g" "$LIB/access-sync.timer.template" > /etc/systemd/system/access-sync.timer
sed "s|__BIN__|$BIN|g; s|__LIB__|$LIB|g" "$LIB/access-update.service.template" > /etc/systemd/system/access-update.service
sed "s|__BIN__|$BIN|g; s|__LIB__|$LIB|g" "$LIB/access-update.timer.template" > /etc/systemd/system/access-update.timer

# Reload systemd and enable services
printf "Reloading systemd...\n"
systemctl daemon-reload

# Enable and start main daemon service
printf "Starting main daemon service...\n"
if systemctl enable access.service && systemctl start access.service; then
    printf "Main daemon service started\n"
else
    printf "WARNING: Failed to start main service\n"
fi

# Enable and start timers
printf "Enabling backup timers...\n"
if systemctl enable access-sync.timer access-update.timer && systemctl start access-sync.timer access-update.timer; then
    printf "Backup timers enabled\n"
else
    printf "WARNING: Failed to enable timers\n"
fi

# Install cron backup jobs
printf "Installing cron backup jobs...\n"
_temp_cron=$(mktemp)
crontab -l 2>/dev/null | grep -v "Access Eternal\|$BIN" > "$_temp_cron" || true
sed "s|__BIN__|$BIN|g; s|__LIB__|$LIB|g" "$LIB/crontab.template" >> "$_temp_cron"
if crontab "$_temp_cron"; then
    printf "Cron backup jobs installed\n"
else
    printf "WARNING: Failed to install cron jobs\n"
fi
rm -f "$_temp_cron"

printf "Access Eternal installation completed!\n"
printf "Services: daemon (real-time) + timers (5min sync, weekly update) + cron backup\n"