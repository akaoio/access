#!/bin/sh

# Provider-specific credential variables (e.g. GODADDY_KEY, CLOUDFLARE_API_TOKEN)
# are intentionally not known here - install.sh stays generic and each
# module/provider/*.sh owns its own fields via the provider_install_* hooks.
# Pre-seed them by exporting the env var the provider expects, e.g.:
#   GODADDY_KEY=xxx GODADDY_SECRET=yyy sudo -E ./install.sh -p godaddy -d example.com -h server1
provider=""
domain=""
host=""

# Transform long options to short ones
for arg in "$@"; do
    shift # Shift all arguments to the left
    case "$arg" in
        --provider) set -- "$@" "-p" ;;
        --domain)   set -- "$@" "-d" ;;
        --host)     set -- "$@" "-h" ;;
        *)          set -- "$@" "$arg" ;;
    esac
done

# Check options
while getopts "p:d:h:" opt; do
    case $opt in
        p) provider="$OPTARG" ;;
        d) domain="$OPTARG" ;;
        h) host="$OPTARG" ;;
        *) printf "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Load init.sh to get all path variables
if [ -f "./init.sh" ]; then
    # Local development - use local init.sh  
    . "./init.sh"
elif [ -f "/usr/local/lib/access/init.sh" ]; then
    # Already installed - use installed init.sh
    . "/usr/local/lib/access/init.sh"
else
    # Remote install - download init.sh from GitHub
    _temp_init=$(mktemp)
    if curl -s https://raw.githubusercontent.com/akaoio/access/main/init.sh > "$_temp_init"; then
        . "$_temp_init"
        rm -f "$_temp_init"
    else
        # Fallback to hardcoded defaults if download fails
        CONFIG="/etc/access/config.env"
        BIN="/usr/local/bin/access"
        LIB="/usr/local/lib/access"
        STATE="/var/lib/access"
        INSTALLED=false
        YN="Please answer [Y]es or [N]o"
        ABORTED="Installation aborted."
        
        # Define prompt_input function since init.sh not available
        prompt_input() {
            _prompt="$1"
            _validation_type="${2:-any}"
            _abort_msg="$3"
            
            while true; do
                printf "%s: " "$_prompt"
                if [ -c /dev/tty ]; then
                    read -r _input < /dev/tty
                else
                    read -r _input
                fi
                
                case "$_validation_type" in
                    "yes_no")
                        case "$_input" in
                            [Yy]*) return 0 ;;
                            [Nn]*) 
                                [ -n "$_abort_msg" ] && printf "%s\n" "$_abort_msg"
                                return 1 ;;
                            *) printf "Please enter Y or N. " ;;
                        esac
                        ;;
                    "non_empty")
                        if [ -n "$_input" ]; then
                            PROMPT_RESULT="$_input"
                            return 0
                        else
                            printf "Input cannot be empty. "
                        fi
                        ;;
                    *) PROMPT_RESULT="$_input"; return 0 ;;
                esac
            done
        }
    fi
fi

# Install git if not exists
if ! command -v git >/dev/null 2>&1; then
    apt update && apt install -y git
fi

# Clone/update access repo to $LIB directory - force fresh clone
rm -rf "$LIB"
git clone -b main https://github.com/akaoio/access "$LIB"

# Check if Access is installed
# If Access is already installed, ask if the user wants to reinstall it
if [ "$INSTALLED" = true ]; then
    printf "Access is already installed! Do you want to reinstall it? [y/N]: "
    if [ -c /dev/tty ]; then read -r confirm < /dev/tty; else read -r confirm; fi
    case "$confirm" in
        [Yy]*) ;;
        *) printf "Installation aborted.\n"; exit 1 ;;
    esac
fi

# Prompt for DNS provider
if [ -z "$provider" ]; then
    printf "Select your DNS provider:\n"
    printf "  1) GoDaddy\n"
    printf "  2) Cloudflare\n"
    printf "Enter choice [1-2]: "
    if [ -c /dev/tty ]; then read -r _provider_choice < /dev/tty; else read -r _provider_choice; fi
    case "$_provider_choice" in
        2) provider="cloudflare" ;;
        *) provider="godaddy" ;;
    esac
fi
if [ ! -f "$LIB/module/provider/$provider.sh" ]; then
    printf "Unknown provider '%s'. Must match a file in module/provider/.\n" "$provider"
    exit 1
fi
. "$LIB/module/provider/$provider.sh"

if [ -z "$domain" ]; then
    printf "Enter your domain name: "
    if [ -c /dev/tty ]; then read -r domain < /dev/tty; else read -r domain; fi
fi

if [ -z "$host" ]; then
    printf "Enter your host name: "
    if [ -c /dev/tty ]; then read -r host < /dev/tty; else read -r host; fi
fi

# Provider-owned prompting: credentials plus anything that depends on the
# domain/host (e.g. Cloudflare resolving its Zone ID)
provider_install_prompt "$domain" "$host"

# Confirm values
printf "Please confirm the following values:\n"
printf "Provider: %s\n" "$provider"
printf "Domain: %s\n" "$domain"
printf "Host: %s\n" "$host"
provider_install_summary
printf "Continue with these values? [y/N]: "
if [ -c /dev/tty ]; then read -r confirm < /dev/tty; else read -r confirm; fi
case "$confirm" in
    [Yy]*) ;;
    *) printf "Installation aborted.\n"; exit 1 ;;
esac

# Backup current config file if exists
if [ -f "$CONFIG" ]; then
    mv "$CONFIG" "$CONFIG.$(date +%s).bak"
fi

# Create config directory and write the config file: generic fields here,
# provider-specific fields appended by the provider module itself
printf "Creating config directory...\n"
mkdir -p "$(dirname "$CONFIG")"
{
    printf "PROVIDER=%s\n" "$provider"
    printf "DOMAIN=%s\n" "$domain"
    printf "HOST=%s\n" "$host"
} > "$CONFIG"
provider_write_config "$CONFIG"
printf "Config file created at %s\n" "$CONFIG"

# Copy entry executable file, this makes Access available globally
printf "Copying executable...\n"
cp "$LIB/access" "$BIN"
chmod +x "$BIN"
# Make daemon executable
chmod +x "$LIB/daemon.sh"
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
sed "s|__BIN__|$BIN|g" "$LIB/crontab.template" >> "$_temp_cron"
if crontab "$_temp_cron"; then
    printf "Cron backup jobs installed\n"
else
    printf "WARNING: Failed to install cron jobs\n"
fi
rm -f "$_temp_cron"

printf "Access Eternal installation completed!\n"
printf "Services: daemon (real-time) + timers (5min sync, weekly update) + cron backup\n"