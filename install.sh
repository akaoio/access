#!/bin/sh

provider=""
godaddy_key=""
godaddy_secret=""
cloudflare_token=""
cloudflare_zone_id=""
domain=""
host=""

# Transform long options to short ones
for arg in "$@"; do
    shift # Shift all arguments to the left
    case "$arg" in
        --provider)          set -- "$@" "-p" ;;
        --godaddy_key)       set -- "$@" "-k" ;;
        --godaddy_secret)    set -- "$@" "-s" ;;
        --cloudflare_token)  set -- "$@" "-t" ;;
        --cloudflare_zone)   set -- "$@" "-z" ;;
        --domain)            set -- "$@" "-d" ;;
        --host)              set -- "$@" "-h" ;;
        *)                   set -- "$@" "$arg" ;;
    esac
done

# Check options
while getopts "p:k:s:t:z:d:h:" opt; do
    case $opt in
        p) provider="$OPTARG" ;;
        k) godaddy_key="$OPTARG" ;;
        s) godaddy_secret="$OPTARG" ;;
        t) cloudflare_token="$OPTARG" ;;
        z) cloudflare_zone_id="$OPTARG" ;;
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
case "$provider" in
    godaddy|cloudflare) ;;
    *) printf "Unknown provider '%s'. Must be 'godaddy' or 'cloudflare'.\n" "$provider"; exit 1 ;;
esac

# Prompt for provider-specific credentials
if [ "$provider" = "godaddy" ]; then
    if [ -z "$godaddy_key" ]; then
        printf "Enter your GoDaddy API Key: "
        if [ -c /dev/tty ]; then read -r godaddy_key < /dev/tty; else read -r godaddy_key; fi
    fi

    if [ -z "$godaddy_secret" ]; then
        printf "Enter your GoDaddy API Secret: "
        if [ -c /dev/tty ]; then read -r godaddy_secret < /dev/tty; else read -r godaddy_secret; fi
    fi
else
    if [ -z "$cloudflare_token" ]; then
        printf "Enter your Cloudflare API Token (needs Zone:Read + DNS:Edit permissions): "
        if [ -c /dev/tty ]; then read -r cloudflare_token < /dev/tty; else read -r cloudflare_token; fi
    fi
fi

if [ -z "$domain" ]; then
    printf "Enter your domain name: "
    if [ -c /dev/tty ]; then read -r domain < /dev/tty; else read -r domain; fi
fi

if [ -z "$host" ]; then
    printf "Enter your host name: "
    if [ -c /dev/tty ]; then read -r host < /dev/tty; else read -r host; fi
fi

# Resolve Cloudflare Zone ID from the domain if not already supplied
if [ "$provider" = "cloudflare" ] && [ -z "$cloudflare_zone_id" ]; then
    printf "Resolving Cloudflare Zone ID for %s...\n" "$domain"
    _cf_zone_resp=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$domain" \
        -H "Authorization: Bearer $cloudflare_token" \
        -H "Content-Type: application/json")
    # Cloudflare's zone object nests other "id" fields (account.id, plan.id, ...)
    # after its own id, so grab the first match in appearance order, not a
    # greedy sed match which would silently grab the wrong (later) one.
    cloudflare_zone_id=$(printf "%s" "$_cf_zone_resp" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"\([^"]*\)"/\1/')
    if [ -z "$cloudflare_zone_id" ]; then
        printf "WARNING: Could not auto-resolve Zone ID (check token permissions and domain).\n"
        printf "Enter your Cloudflare Zone ID manually (Cloudflare dashboard > your domain > Overview > API section): "
        if [ -c /dev/tty ]; then read -r cloudflare_zone_id < /dev/tty; else read -r cloudflare_zone_id; fi
    else
        printf "Resolved Zone ID: %s\n" "$cloudflare_zone_id"
    fi
fi

# Confirm values
printf "Please confirm the following values:\n"
printf "Provider: %s\n" "$provider"
if [ "$provider" = "godaddy" ]; then
    printf "GoDaddy API Key: %s\n" "$godaddy_key"
    printf "GoDaddy API Secret: %s\n" "$godaddy_secret"
else
    printf "Cloudflare API Token: %s\n" "$cloudflare_token"
    printf "Cloudflare Zone ID: %s\n" "$cloudflare_zone_id"
fi
printf "Domain: %s\n" "$domain"
printf "Host: %s\n" "$host"
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

# Create config directory and generate config from template
printf "Creating config directory...\n"
mkdir -p "$(dirname "$CONFIG")"
printf "Processing config template...\n"
sed "s/__PROVIDER__/$provider/g; s/__GODADDY_KEY__/$godaddy_key/g; s/__GODADDY_SECRET__/$godaddy_secret/g; s/__CLOUDFLARE_API_TOKEN__/$cloudflare_token/g; s/__CLOUDFLARE_ZONE_ID__/$cloudflare_zone_id/g; s/__DOMAIN__/$domain/g; s/__HOST__/$host/g" "$LIB/config.env.template" > "$CONFIG"
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

# Generate access.service directly with correct content
cat > /etc/systemd/system/access.service << EOF
[Unit]
Description=Access Eternal - Real-time IP Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=$LIB/daemon.sh
StandardOutput=append:/var/log/access/access.log
StandardError=append:/var/log/access/error.log

[Install]
WantedBy=multi-user.target
EOF
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
cat >> "$_temp_cron" << EOF
# Access Eternal - Cron backup jobs
# DNS sync every 5 minutes (backup to systemd timer)
*/5 * * * * $BIN sync >> /var/log/access/access.log 2>> /var/log/access/error.log

# Auto update every Sunday at 3 AM (backup to systemd timer)  
0 3 * * 0 $BIN update >> /var/log/access/access.log 2>> /var/log/access/error.log

EOF
if crontab "$_temp_cron"; then
    printf "Cron backup jobs installed\n"
else
    printf "WARNING: Failed to install cron jobs\n"
fi
rm -f "$_temp_cron"

printf "Access Eternal installation completed!\n"
printf "Services: daemon (real-time) + timers (5min sync, weekly update) + cron backup\n"