#!/bin/sh
# Access - Pure shell network access layer with modular provider support
# The eternal foundation that enables connectivity

VERSION="0.0.3"

# Color support
if [ "${FORCE_COLOR:-0}" = "1" ] || { [ -t 1 ] && [ "${NO_COLOR:-0}" != "1" ] && [ "${TERM:-}" != "dumb" ]; }; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    DIM=''
    NC=''
fi

# Color logging functions
log_success() {
    echo "${GREEN}✓${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*" >> "$ACCESS_LOG"
}

log_error() {
    if [ -n "$RED" ]; then
        echo "${RED}✗ Error:${NC} $*" >&2
    else
        echo "Error: $*" >&2
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$ACCESS_LOG"
}


log_info() {
    echo "${BLUE}ℹ${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$ACCESS_LOG"
}

log_debug() {
    if [ "${ACCESS_DEBUG:-0}" = "1" ]; then
        echo "${DIM}[DEBUG]${NC} $*" >&2
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" >> "$ACCESS_LOG"
    fi
}

# Cleanup on exit
cleanup() {
    # Remove any temp files
    rm -f /tmp/access_* 2>/dev/null
}
trap cleanup EXIT INT TERM
# XDG Base Directory Specification compliance
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Access directories following XDG standard
ACCESS_CONFIG_HOME="${ACCESS_CONFIG_HOME:-$XDG_CONFIG_HOME/access}"
ACCESS_DATA_HOME="${ACCESS_DATA_HOME:-$XDG_DATA_HOME/access}"

# Configuration files (XDG-compliant)
ACCESS_CONFIG="${ACCESS_CONFIG:-$ACCESS_CONFIG_HOME/config.json}"
ACCESS_STATE="${ACCESS_STATE:-$ACCESS_DATA_HOME/state.json}"
ACCESS_LOG="${ACCESS_LOG:-$ACCESS_DATA_HOME/access.log}"

# Get script directory for provider loading
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure XDG-compliant directories exist
mkdir -p "$ACCESS_CONFIG_HOME"
mkdir -p "$ACCESS_DATA_HOME"

# Source provider abstraction layer
if [ -f "$SCRIPT_DIR/providers.sh" ]; then
    . "$SCRIPT_DIR/providers.sh"
else
    log_error "Provider abstraction layer not found"
    exit 1
fi

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ACCESS_LOG"
}

# IPv4 validation
validate_ipv4() {
    echo "$1" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || return 1
    
    # Check each octet
    IFS='.' read -r a b c d <<EOF
$1
EOF
    [ "$a" -le 255 ] && [ "$b" -le 255 ] && [ "$c" -le 255 ] && [ "$d" -le 255 ] || return 1
    
    # Exclude private/reserved ranges
    [ "$a" -eq 10 ] && return 1
    [ "$a" -eq 127 ] && return 1
    [ "$a" -eq 0 ] && return 1
    [ "$a" -ge 224 ] && return 1
    [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ] && return 1
    [ "$a" -eq 192 ] && [ "$b" -eq 168 ] && return 1
    
    return 0
}

# IPv6 validation
validate_ipv6() {
    local ip="$1"
    
    # Empty or too short
    [ -z "$ip" ] && return 1
    [ ${#ip} -lt 2 ] && return 1
    
    # Basic IPv6 format check - allow :: and standard hex groups
    echo "$ip" | grep -qE '^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$|^::$|^::1$|^[0-9a-fA-F:]+::$|^::[0-9a-fA-F:]+$' || return 1
    
    # Exclude private/reserved ranges
    case "$ip" in
        ::1|::1/*) return 1 ;;                          # Loopback
        fe80:*|fe80::*) return 1 ;;                     # Link-local
        fc00:*|fd00:*) return 1 ;;                      # Unique local
        ff00:*) return 1 ;;                             # Multicast
        ::) return 1 ;;                                 # Unspecified
    esac
    
    return 0
}


# Detect public IPv6 via DNS
detect_ipv6_dns() {
    local ip=""
    
    # Try OpenDNS IPv6
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short myip.opendns.com @2620:119:35::35 AAAA 2>/dev/null | head -n1)
        if validate_ipv6 "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Try Google IPv6 DNS
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short @2001:4860:4860::8888 myip.opendns.com AAAA 2>/dev/null | head -n1)
        if validate_ipv6 "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    return 1
}

# Detect public IPv4 via DNS
detect_ipv4_dns() {
    local ip=""
    
    # Try OpenDNS
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -n1)
        if validate_ipv4 "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Try nslookup
    if command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup myip.opendns.com resolver1.opendns.com 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
        if validate_ipv4 "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    return 1
}

# Detect public IP via DNS (IPv6 priority)
detect_ip_dns() {
    local ip=""
    
    # Try IPv6 first
    ip=$(detect_ipv6_dns)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fall back to IPv4
    ip=$(detect_ipv4_dns)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

# Detect public IPv6 via HTTP
detect_ipv6_http() {
    local ip=""
    local services="https://ipv6.icanhazip.com https://v6.ident.me https://ipv6.whatismyip.akamai.com"
    
    for service in $services; do
        # Try curl with IPv6
        if command -v curl >/dev/null 2>&1; then
            ip=$(curl -s -6 --max-time ${ACCESS_TIMEOUT:-5} "$service" 2>/dev/null | tr -d '\n\r' | head -n1)
            if validate_ipv6 "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Try wget with IPv6
        if command -v wget >/dev/null 2>&1; then
            ip=$(wget -qO- -6 --timeout=${ACCESS_TIMEOUT:-5} "$service" 2>/dev/null | tr -d '\n\r' | head -n1)
            if validate_ipv6 "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    return 1
}

# Detect public IPv4 via HTTP
detect_ipv4_http() {
    local ip=""
    local services="https://checkip.amazonaws.com https://ipv4.icanhazip.com https://ifconfig.me"
    
    for service in $services; do
        # Try curl
        if command -v curl >/dev/null 2>&1; then
            ip=$(curl -s -4 --max-time ${ACCESS_TIMEOUT:-5} "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
            if validate_ipv4 "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Try wget
        if command -v wget >/dev/null 2>&1; then
            ip=$(wget -qO- -4 --timeout=${ACCESS_TIMEOUT:-5} "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
            if validate_ipv4 "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    return 1
}

# Detect public IP via HTTP (IPv6 priority)
detect_ip_http() {
    local ip=""
    
    # Try IPv6 first
    ip=$(detect_ipv6_http)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fall back to IPv4
    ip=$(detect_ipv4_http)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

# Main IP detection (IPv6 priority)
detect_ip() {
    local ip=""
    
    # Try DNS first (fastest)
    ip=$(detect_ip_dns)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fall back to HTTP
    ip=$(detect_ip_http)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

# Force IPv4 detection only
detect_ipv4() {
    local ip=""
    
    # Try DNS first
    ip=$(detect_ipv4_dns)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fall back to HTTP
    ip=$(detect_ipv4_http)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

# Force IPv6 detection only
detect_ipv6() {
    local ip=""
    
    # Try DNS first
    ip=$(detect_ipv6_dns)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fall back to HTTP
    ip=$(detect_ipv6_http)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    return 1
}

# Lock file management for redundant automation (XDG data directory)
LOCK_FILE="$ACCESS_DATA_HOME/access.lock"
LAST_RUN_FILE="$ACCESS_DATA_HOME/last_run"

# Check if another instance is running and should skip
should_skip_redundant() {
    local current_time=$(date +%s)
    local lock_timeout=600  # 10 minutes
    local min_interval=180  # 3 minutes minimum between runs (less than 5 min cron interval)
    
    # Check lock file
    if [ -f "$LOCK_FILE" ]; then
        local lock_time=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        local lock_age=$((current_time - lock_time))
        
        # If lock is fresh (< 10 minutes), another instance might be running
        if [ "$lock_age" -lt "$lock_timeout" ]; then
            # Check if process is actually running
            local lock_pid=$(ps aux | grep "access.*daemon\|access.*update" | grep -v grep | head -1 | awk '{print $2}')
            if [ -n "$lock_pid" ]; then
                log "Another Access instance running (PID: $lock_pid) - skipping"
                return 0  # Skip
            fi
        fi
    fi
    
    # Check last run time
    if [ -f "$LAST_RUN_FILE" ]; then
        local last_run=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
        local run_age=$((current_time - last_run))
        
        # If last run was recent, skip to avoid conflicts
        if [ "$run_age" -lt "$min_interval" ]; then
            log "Recent run detected ($run_age seconds ago) - skipping to avoid conflict"
            return 0  # Skip
        fi
    fi
    
    return 1  # Don't skip
}

# Create lock and update last run
create_run_lock() {
    local current_time=$(date +%s)
    echo "$current_time" > "$LOCK_FILE"
    echo "$current_time" > "$LAST_RUN_FILE"
}

# Remove lock
remove_run_lock() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

# Load configuration
load_config() {
    if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
        # Use jq if available
        PROVIDER=$(jq -r '.provider // ""' "$ACCESS_CONFIG")
        DOMAIN=$(jq -r '.domain // ""' "$ACCESS_CONFIG")
        HOST=$(jq -r '.host // ""' "$ACCESS_CONFIG")
        
        # Load provider-specific config as environment variables
        if [ -n "$PROVIDER" ]; then
            local prefix=$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')
            
            # Export provider-specific fields (avoid subshell to make export work)
            local temp_file=$(mktemp)
            jq -r ".[\"$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')\"] // {} | to_entries | .[] | \"export ${prefix}_\\(.key | ascii_upcase)=\\(.value)\"" "$ACCESS_CONFIG" 2>/dev/null > "$temp_file"
            if [ -s "$temp_file" ]; then
                . "$temp_file"
            fi
            rm -f "$temp_file"
        fi
    elif [ -f "$ACCESS_CONFIG" ]; then
        # Fallback to grep/sed parsing
        PROVIDER=$(grep '"provider"' "$ACCESS_CONFIG" | sed 's/.*"provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        DOMAIN=$(grep '"domain"' "$ACCESS_CONFIG" | sed 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        HOST=$(grep '"host"' "$ACCESS_CONFIG" | sed 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    
    # Environment overrides
    PROVIDER="${ACCESS_PROVIDER:-$PROVIDER}"
    DOMAIN="${ACCESS_DOMAIN:-$DOMAIN}"
    HOST="${ACCESS_HOST:-$HOST}"
    
    # Handle empty host based on discovery setting
    if [ -z "$HOST" ]; then
        # Check if discovery is enabled (from config or environment)
        DISCOVERY_ENABLED="${ACCESS_DISCOVERY:-false}"
        if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
            DISCOVERY_ENABLED=$(jq -r '.discovery // false' "$ACCESS_CONFIG" 2>/dev/null || echo "false")
        fi
        
        if [ "$DISCOVERY_ENABLED" = "true" ] && [ -n "$DOMAIN" ]; then
            log "Host is empty with discovery enabled - finding available slot..."
            
            # Check if discovery.sh exists
            DISCOVERY_SCRIPT="$(dirname "$0")/discovery.sh"
            if [ ! -f "$DISCOVERY_SCRIPT" ]; then
                # Try installed location
                DISCOVERY_SCRIPT="/usr/local/bin/access-discovery"
                if [ ! -f "$DISCOVERY_SCRIPT" ]; then
                    # Try user location
                    DISCOVERY_SCRIPT="$HOME/.local/bin/access-discovery"
                fi
            fi
            
            if [ -f "$DISCOVERY_SCRIPT" ] && [ -x "$DISCOVERY_SCRIPT" ]; then
                # Source discovery functions
                . "$DISCOVERY_SCRIPT"
                
                # Set discovery variables
                DOMAIN="$DOMAIN"
                HOST_PREFIX="${HOST_PREFIX:-peer}"
                
                # Find available slot
                if slot=$(find_lowest_available_slot); then
                    HOST="${HOST_PREFIX}${slot}"
                    log_success "Auto-discovered available host: $HOST"
                    
                    # Save the discovered host back to config
                    if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
                        temp_file=$(mktemp)
                        jq ".host = \"$HOST\"" "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
                        log "Saved auto-discovered host to configuration"
                    fi
                else
                    log_warning "Auto-discovery failed - using root domain (@)"
                    HOST="@"
                fi
            else
                log_warning "Discovery module not found - using root domain (@)"
                HOST="@"
            fi
        else
            # Discovery not enabled or no domain - use root
            log_debug "Host empty, discovery disabled - using root domain (@)"
            HOST="@"
        fi
    fi
    
    # Default to @ if still empty (fallback)
    HOST="${HOST:-@}"
}

# Save configuration
save_config() {
    local provider="$1"
    shift
    
    # Start JSON
    local config_json="{\n    \"provider\": \"$provider\",\n    \"domain\": \"$DOMAIN\",\n    \"host\": \"$HOST\""
    
    # Add provider-specific configuration
    if [ -n "$provider" ]; then
        local provider_lower=$(echo "$provider" | tr '[:upper:]' '[:lower:]')
        local provider_upper=$(echo "$provider" | tr '[:lower:]' '[:upper:]')
        
        config_json="$config_json,\n    \"$provider_lower\": {"
        
        # Build provider config fields properly (avoid subshell issue)
        local provider_fields=""
        local field_count=0
        
        for env_var in $(env | grep "^${provider_upper}_" | cut -d= -f1); do
            env_value=$(eval echo "\$$env_var")
            field_name=$(echo "$env_var" | sed "s/^${provider_upper}_//g" | tr '[:upper:]' '[:lower:]')
            
            if [ $field_count -gt 0 ]; then
                provider_fields="${provider_fields},"
            fi
            provider_fields="${provider_fields}\n        \"$field_name\": \"$env_value\""
            field_count=$(expr $field_count + 1)
        done
        
        config_json="$config_json$provider_fields\n    }"
    fi
    
    config_json="$config_json\n}"
    
    # Add discovery flag if set in environment
    if [ -n "$DISCOVERY_ENABLED" ]; then
        # Parse existing config and add discovery flag
        if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
            # First save the basic config
            printf "%b\n" "$config_json" > "$ACCESS_CONFIG"
            # Then add discovery flag using jq
            temp_file=$(mktemp)
            jq ".discovery = $DISCOVERY_ENABLED" "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
        else
            # Fallback: manually add discovery field before closing brace
            config_json=$(echo "$config_json" | sed 's/\n}$/,\n    "discovery": '"$DISCOVERY_ENABLED"'\n}/')
            printf "%b\n" "$config_json" > "$ACCESS_CONFIG"
        fi
    else
        printf "%b\n" "$config_json" > "$ACCESS_CONFIG"
    fi
    
    log "Configuration saved to $ACCESS_CONFIG"
    log "Provider: $provider, Domain: $DOMAIN, Host: $HOST"
}

# Self-update using Manager framework
self_update() {
    log "Checking for updates using Manager framework..."
    
    # Find Manager in various locations
    local manager_found=false
    local manager_dirs="$HOME/manager /usr/local/lib/manager"
    
    # Also check if we can access root's manager (for system installations)
    if [ -r "/root/manager/manager-self-update.sh" ]; then
        manager_dirs="$manager_dirs /root/manager"
    fi
    
    local manager_dir=""
    for dir in $manager_dirs; do
        if [ -f "$dir/manager-self-update.sh" ]; then
            log "Loading Manager from $dir"
            manager_dir="$dir"
            manager_found=true
            break
        fi
    done
    
    if [ "$manager_found" = false ]; then
        # Try to clone Manager if not found
        log "Manager not found. Installing Manager framework..."
        git clone https://github.com/akaoio/manager.git "$HOME/manager" || {
            log "Failed to install Manager framework"
            return 1
        }
        manager_dir="$HOME/manager"
    fi
    
    # Load all Manager modules needed
    if [ -f "$manager_dir/manager-core.sh" ]; then
        . "$manager_dir/manager-core.sh"
    fi
    if [ -f "$manager_dir/manager-update.sh" ]; then
        . "$manager_dir/manager-update.sh"
    fi
    
    # Initialize Manager environment variables for Access
    export MANAGER_CLEAN_CLONE_DIR="/home/x/access"
    export MANAGER_CONFIG_DIR="$HOME/.config/access"
    
    # Now run the actual update
    log "Running update check..."
    
    # Parse arguments to determine action
    action="check"
    shift  # Remove 'self-update' argument
    for arg in "$@"; do
        case "$arg" in
            --apply|--update|--install) action="apply" ;;
            --check) action="check" ;;
            --status) action="status" ;;
        esac
    done
    
    # Use the correct Manager update functions
    case "$action" in
        apply)
            if command -v manager_apply_updates >/dev/null 2>&1; then
                log "Applying updates..."
                manager_apply_updates || {
                    log "Update application completed"
                }
            else
                log "Manager update functions not available"
                return 1
            fi
            ;;
        status)
            if command -v manager_check_updates >/dev/null 2>&1; then
                if manager_check_updates; then
                    log "Updates are available"
                    return 0
                else
                    log "Already up to date"
                    return 1
                fi
            fi
            ;;
        check|*)
            if command -v manager_check_updates >/dev/null 2>&1; then
                if manager_check_updates; then
                    log "Updates are available. Run 'access self-update --apply' to install"
                    return 0
                else
                    log "Already up to date"
                    return 1
                fi
            else
                log "Manager update functions not available"
                return 1
            fi
            ;;
    esac
    
    log "Update check completed"
}

# Main command handler
case "${1:-help}" in
    ip)
        ip=$(detect_ip)
        if [ $? -eq 0 ]; then
            if validate_ipv6 "$ip"; then
                log_success "Detected IPv6: $ip"
            else
                log_success "Detected IPv4: $ip"
            fi
            echo "$ip"
        else
            log_error "Failed to detect IP"
            exit 1
        fi
        ;;
        
    ipv4)
        ip=$(detect_ipv4)
        if [ $? -eq 0 ]; then
            log_success "Detected IPv4: $ip"
            echo "$ip"
        else
            log_error "Failed to detect IPv4"
            exit 1
        fi
        ;;
        
    ipv6)
        ip=$(detect_ipv6)
        if [ $? -eq 0 ]; then
            log_success "Detected IPv6: $ip"
            echo "$ip"
        else
            log_error "Failed to detect IPv6"
            exit 1
        fi
        ;;
        
    update)
        # Check for redundant automation conflict avoidance
        if should_skip_redundant; then
            exit 0
        fi
        
        # Create run lock
        create_run_lock
        trap 'remove_run_lock; exit 130' INT TERM
        
        # Check for updates first (optional)
        # Auto-update removed - use Manager framework instead
        
        load_config
        
        if [ -z "$PROVIDER" ]; then
            log_error "No provider configured"
            log_info "Run: access config <provider> --help"
            remove_run_lock
            exit 1
        fi
        
        ip=$(detect_ip)
        if [ $? -ne 0 ]; then
            log_error "Failed to detect IP"
            remove_run_lock
            exit 1
        fi
        
        log_success "Detected IP: $ip"
        log_info "Using provider: $PROVIDER"
        
        # Use provider abstraction to update DNS
        update_with_provider "$PROVIDER" "$DOMAIN" "$HOST" "$ip"
        
        # Remove lock on successful completion
        remove_run_lock
        ;;
        
    config)
        shift
        PROVIDER="${1}"
        
        if [ -z "$PROVIDER" ]; then
            log_error "Provider not specified"
            echo ""
            list_providers
            echo ""
            echo "${YELLOW}Usage:${NC} access config <provider> [options]"
            exit 1
        fi
        
        shift
        
        # Check if provider exists
        if ! load_provider "$PROVIDER"; then
            exit 1
        fi
        
        # Show help if requested
        if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
            get_provider_config "$PROVIDER"
            exit 0
        fi
        
        # Parse arguments based on provider requirements
        prefix=$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')
        
        for arg in "$@"; do
            case "$arg" in
                --domain=*) DOMAIN="${arg#*=}" ;;
                --host=*) HOST="${arg#*=}" ;;
                --discovery=*) 
                    DISCOVERY_ENABLED="${arg#*=}"
                    # Validate boolean value
                    case "$DISCOVERY_ENABLED" in
                        true|false) ;;
                        *) 
                            log_error "Invalid discovery value: $DISCOVERY_ENABLED (must be true or false)"
                            exit 1
                            ;;
                    esac
                    ;;
                --*=*)
                    # Generic handling for provider-specific arguments
                    key=$(echo "${arg%%=*}" | sed 's/^--//' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                    value="${arg#*=}"
                    export "${prefix}_${key}=$value"
                    ;;
            esac
        done
        
        # Validate configuration
        if [ -z "$DOMAIN" ]; then
            log_error "Domain is required"
            get_provider_config "$PROVIDER"
            exit 1
        fi
        
        # Save configuration
        save_config "$PROVIDER"
        ;;
        
    daemon)
        log "Starting Access daemon (redundant with cron backup)..."
        
        # Create daemon-specific lock for service identification (XDG data directory)
        DAEMON_LOCK="$ACCESS_DATA_HOME/daemon.lock"
        echo $$ > "$DAEMON_LOCK"
        trap 'rm -f "$DAEMON_LOCK"; remove_run_lock; exit 130' INT TERM
        
        while true; do
            # Check if we should skip this cycle due to redundancy
            if should_skip_redundant; then
                log "Cron recently ran - daemon cycle skipped (backup working)"
            else
                log "Daemon cycle - updating DNS..."
                create_run_lock
                
                # Run update with direct call to avoid recursive redundancy checks
                load_config
                
                if [ -n "$PROVIDER" ]; then
                    ip=$(detect_ip)
                    if [ $? -eq 0 ]; then
                        log_success "Detected IP: $ip"
                        log_info "Using provider: $PROVIDER"
                        update_with_provider "$PROVIDER" "$DOMAIN" "$HOST" "$ip"
                    else
                        log_error "Failed to detect IP"
                    fi
                else
                    log_error "No provider configured"
                fi
                
                remove_run_lock
            fi
            
            sleep "${ACCESS_INTERVAL:-300}"
        done
        ;;
        
    providers)
        list_providers
        ;;
        
    discovery)
        # Manage network discovery settings
        shift
        if [ "$1" = "enable" ]; then
            if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
                temp_file=$(mktemp)
                jq '.discovery = true' "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
                log_success "Network discovery enabled"
                log "When host is empty, Access will auto-discover available peer slots"
            else
                log_error "Config file not found. Run 'access config <provider>' first"
                exit 1
            fi
        elif [ "$1" = "disable" ]; then
            if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
                temp_file=$(mktemp)
                jq '.discovery = false' "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
                log_success "Network discovery disabled"
                log "When host is empty, Access will use root domain (@)"
            else
                log_error "Config file not found. Run 'access config <provider>' first"
                exit 1
            fi
        elif [ "$1" = "status" ] || [ -z "$1" ]; then
            if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
                discovery_status=$(jq -r '.discovery // false' "$ACCESS_CONFIG" 2>/dev/null || echo "false")
                echo "Network discovery: $discovery_status"
                if [ "$discovery_status" = "true" ]; then
                    echo "  When host is empty, auto-discovery will find available peer slots"
                else
                    echo "  When host is empty, root domain (@) will be used"
                fi
            else
                echo "Network discovery: not configured"
                echo "  Run 'access config <provider>' first"
            fi
        else
            echo "Usage: access discovery [enable|disable|status]"
            echo ""
            echo "  enable   - Enable auto-discovery for empty host"
            echo "  disable  - Disable auto-discovery (use @ for empty host)"
            echo "  status   - Show current discovery setting (default)"
            exit 1
        fi
        ;;
        
    discover)
        # Auto-discover providers without hardcoding
        echo "Available providers (auto-discovered):"
        echo ""
        discover_providers
        ;;
        
    capabilities)
        shift
        if [ -z "$1" ]; then
            echo "Usage: access capabilities <provider>"
            exit 1
        fi
        
        if command -v get_provider_capabilities >/dev/null 2>&1; then
            get_provider_capabilities "$1"
        else
            log_error "Provider system not loaded - check SCRIPT_DIR: $SCRIPT_DIR"
            exit 1
        fi
        ;;
        
    suggest)
        shift
        if [ -z "$1" ]; then
            echo "Usage: access suggest <domain>"
            exit 1
        fi
        suggest_provider "$1"
        ;;
        
    health)
        check_provider_health
        ;;
        
    test)
        shift
        if [ -z "$1" ]; then
            load_config
            if [ -z "$PROVIDER" ]; then
                log_error "No provider configured"
                exit 1
            fi
            test_provider "$PROVIDER"
        else
            test_provider "$1"
        fi
        ;;
        
    self-update)
        self_update "$@"
        ;;
        
    status)
        # Show current configuration and status
        echo "${BOLD}Access Configuration Status${NC}"
        echo "${BOLD}===========================${NC}"
        echo ""
        
        # Load and display current config
        load_config
        
        if [ -f "$ACCESS_CONFIG" ]; then
            echo "${GREEN}Configuration file:${NC} $ACCESS_CONFIG"
            echo ""
            echo "${BOLD}Current settings:${NC}"
            echo "  Provider: ${YELLOW}${PROVIDER:-not configured}${NC}"
            echo "  Domain: ${YELLOW}${DOMAIN:-not configured}${NC}"
            echo "  Host: ${YELLOW}${HOST:-not configured}${NC}"
            
            # Show discovery status
            if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
                discovery_status=$(jq -r '.discovery // false' "$ACCESS_CONFIG" 2>/dev/null || echo "false")
                echo "  Discovery: ${YELLOW}$discovery_status${NC}"
            fi
            
            # Show provider-specific config (without sensitive data)
            if [ -n "$PROVIDER" ]; then
                echo ""
                echo "${BOLD}Provider settings:${NC}"
                case "$PROVIDER" in
                    godaddy)
                        [ -n "$GODADDY_KEY" ] && echo "  API Key: ${DIM}configured${NC}"
                        [ -n "$GODADDY_SECRET" ] && echo "  API Secret: ${DIM}configured${NC}"
                        ;;
                    cloudflare)
                        [ -n "$CLOUDFLARE_EMAIL" ] && echo "  Email: ${YELLOW}$CLOUDFLARE_EMAIL${NC}"
                        [ -n "$CLOUDFLARE_API_KEY" ] && echo "  API Key: ${DIM}configured${NC}"
                        [ -n "$CLOUDFLARE_ZONE_ID" ] && echo "  Zone ID: ${DIM}configured${NC}"
                        ;;
                    *)
                        echo "  ${DIM}Provider-specific settings configured${NC}"
                        ;;
                esac
            fi
        else
            echo "${RED}No configuration found${NC}"
            echo "  Run: ${YELLOW}access config <provider> --domain=<domain>${NC}"
        fi
        
        # Show service status
        echo ""
        echo "${BOLD}Service status:${NC}"
        
        # Check if running as daemon
        if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
            daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock")
            if kill -0 "$daemon_pid" 2>/dev/null; then
                echo "  Daemon: ${GREEN}running${NC} (PID: $daemon_pid)"
            else
                echo "  Daemon: ${RED}stale lock${NC} (PID: $daemon_pid)"
            fi
        else
            echo "  Daemon: ${DIM}not running${NC}"
        fi
        
        # Check cron
        if crontab -l 2>/dev/null | grep -q "access update"; then
            echo "  Cron: ${GREEN}configured${NC}"
            cron_schedule=$(crontab -l | grep "access update" | head -1 | cut -d' ' -f1-5)
            echo "    Schedule: ${YELLOW}$cron_schedule${NC}"
        else
            echo "  Cron: ${DIM}not configured${NC}"
        fi
        
        # Check systemd service
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl --user list-unit-files 2>/dev/null | grep -q "^access.service"; then
                service_status=$(systemctl --user is-active access.service 2>/dev/null)
                if [ "$service_status" = "active" ]; then
                    echo "  Systemd: ${GREEN}active${NC} (user service)"
                else
                    echo "  Systemd: ${YELLOW}$service_status${NC} (user service)"
                fi
            elif systemctl list-unit-files 2>/dev/null | grep -q "^access.service"; then
                service_status=$(systemctl is-active access.service 2>/dev/null)
                if [ "$service_status" = "active" ]; then
                    echo "  Systemd: ${GREEN}active${NC} (system service)"
                else
                    echo "  Systemd: ${YELLOW}$service_status${NC} (system service)"
                fi
            else
                echo "  Systemd: ${DIM}not configured${NC}"
            fi
        fi
        
        # Show last update info
        if [ -f "$ACCESS_DATA_HOME/last_run" ]; then
            last_run_timestamp=$(cat "$ACCESS_DATA_HOME/last_run")
            current_time=$(date +%s)
            time_diff=$((current_time - last_run_timestamp))
            
            if [ $time_diff -lt 60 ]; then
                echo ""
                echo "${BOLD}Last update:${NC} ${GREEN}$time_diff seconds ago${NC}"
            elif [ $time_diff -lt 3600 ]; then
                minutes=$((time_diff / 60))
                echo ""
                echo "${BOLD}Last update:${NC} ${GREEN}$minutes minutes ago${NC}"
            elif [ $time_diff -lt 86400 ]; then
                hours=$((time_diff / 3600))
                echo ""
                echo "${BOLD}Last update:${NC} ${YELLOW}$hours hours ago${NC}"
            else
                days=$((time_diff / 86400))
                echo ""
                echo "${BOLD}Last update:${NC} ${RED}$days days ago${NC}"
            fi
            
            # Show current IP
            current_ip=$(detect_ip 2>/dev/null)
            if [ -n "$current_ip" ]; then
                echo "${BOLD}Current IP:${NC} ${CYAN}$current_ip${NC}"
            fi
        else
            echo ""
            echo "${BOLD}Last update:${NC} ${DIM}never${NC}"
        fi
        ;;
        
    logs)
        # View Access logs
        shift
        log_file="$ACCESS_DATA_HOME/access.log"
        
        if [ ! -f "$log_file" ]; then
            log_error "No logs found at $log_file"
            exit 1
        fi
        
        # Parse options
        lines=20
        follow=false
        for arg in "$@"; do
            case "$arg" in
                -f|--follow) follow=true ;;
                -n*) lines="${arg#-n}" ;;
                --lines=*) lines="${arg#*=}" ;;
                --all) lines="" ;;
            esac
        done
        
        if [ "$follow" = true ]; then
            tail -f "$log_file"
        elif [ -z "$lines" ]; then
            cat "$log_file"
        else
            tail -n "$lines" "$log_file"
        fi
        ;;
        
    clean)
        # Clean locks and temporary files
        echo "${BOLD}Cleaning Access temporary files...${NC}"
        
        # Remove stale locks
        if [ -f "$ACCESS_DATA_HOME/run.lock" ]; then
            rm -f "$ACCESS_DATA_HOME/run.lock"
            echo "  ${GREEN}✓${NC} Removed run lock"
        fi
        
        if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
            daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
            if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
                echo "  ${YELLOW}!${NC} Daemon is still running (PID: $daemon_pid)"
                echo "    Use 'pkill -f \"access daemon\"' to stop it first"
            else
                rm -f "$ACCESS_DATA_HOME/daemon.lock"
                echo "  ${GREEN}✓${NC} Removed stale daemon lock"
            fi
        fi
        
        # Clean old logs (keep last 1000 lines)
        if [ -f "$ACCESS_DATA_HOME/access.log" ]; then
            temp_log=$(mktemp)
            tail -n 1000 "$ACCESS_DATA_HOME/access.log" > "$temp_log"
            mv "$temp_log" "$ACCESS_DATA_HOME/access.log"
            echo "  ${GREEN}✓${NC} Trimmed log file (kept last 1000 lines)"
        fi
        
        echo ""
        echo "${GREEN}Cleanup complete${NC}"
        ;;
        
    version)
        echo "${BOLD}Access v$VERSION${NC} - Pure shell DNS synchronization"
        ;;
        
    *)
        echo ""
        echo "${BOLD}================================================================${NC}"
        echo "${BOLD}Access - Dynamic DNS IP Synchronization v$VERSION${NC}"
        echo "${BOLD}================================================================${NC}"
        echo ""
        echo "${BOLD}Usage:${NC}"
        echo "${BOLD}------${NC}"
        echo ""
        echo "${BOLD}Commands:${NC}"
        echo "    ${BLUE}access status${NC}          Show configuration and service status"
        echo "    ${BLUE}access ip${NC}              Detect public IP (IPv6 priority)"
        echo "    ${BLUE}access ipv4${NC}            Force IPv4 detection only"
        echo "    ${BLUE}access ipv6${NC}            Force IPv6 detection only"
        echo "    ${BLUE}access update${NC}          Update DNS with current IP"  
        echo "    ${BLUE}access config${NC}          Configure DNS provider"
        echo "    ${BLUE}access discovery${NC}       Manage auto-discovery settings"
        echo "    ${BLUE}access providers${NC}       List available providers"
        echo "    ${BLUE}access discover${NC}        Auto-discover all providers"
        echo "    ${BLUE}access capabilities${NC}    Show provider capabilities"
        echo "    ${BLUE}access suggest${NC}         Suggest provider for domain"
        echo "    ${BLUE}access health${NC}          Check provider health"
        echo "    ${BLUE}access test${NC} [provider] Test provider connectivity"
        echo "    ${BLUE}access daemon${NC}          Run as daemon (updates every 5 minutes)"
        echo "    ${BLUE}access logs${NC}            View Access logs"
        echo "    ${BLUE}access clean${NC}           Clean locks and temporary files"
        echo "    ${BLUE}access self-update${NC}     Update using Manager framework"
        echo "    ${BLUE}access version${NC}         Show version"
        echo "    ${BLUE}access help${NC}            Show this help"
        echo ""
        echo "${BOLD}Configuration:${NC}"
        echo "${BOLD}-------------${NC}"
        echo "    ${YELLOW}access config${NC} <provider> ${DIM}--help${NC}     Show provider configuration help"
        echo "    ${YELLOW}access config${NC} <provider> ${DIM}[options]${NC}  Configure provider"
        echo "    ${YELLOW}access discovery${NC} [enable|disable]   Manage peer auto-discovery"
        echo ""
        echo "${BOLD}Provider Discovery:${NC}"
        echo "${BOLD}------------------${NC}"
        echo "    ${GREEN}access discover${NC}                     List all discovered providers"
        echo "    ${GREEN}access capabilities${NC} <provider>      Show what a provider can do"
        echo "    ${GREEN}access suggest${NC} <domain>             Auto-suggest provider for domain"
        echo "    ${GREEN}access health${NC}                       Check health of all providers"
        echo ""
        echo "${BOLD}Examples:${NC}"
        echo "${BOLD}---------${NC}"
        echo "  ${BOLD}Configuration:${NC}"
        echo "    ${DIM}access config godaddy --domain=example.com --key=KEY --secret=SECRET${NC}"
        echo "    ${DIM}access config godaddy --domain=example.com --key=KEY --secret=SECRET --discovery=true${NC}"
        echo "    ${DIM}access config cloudflare --domain=example.com --email=EMAIL --api-key=KEY --zone-id=ZONE${NC}"
        echo ""
        echo "  ${BOLD}Daily Usage:${NC}"
        echo "    ${DIM}access status${NC}                               # Check configuration and service status"
        echo "    ${DIM}access ip${NC}                                   # Show current public IP"
        echo "    ${DIM}access update${NC}                               # Update DNS immediately"
        echo "    ${DIM}access discovery enable${NC}                     # Enable peer auto-discovery"
        echo "    ${DIM}access logs -f${NC}                              # Follow real-time logs"
        echo "    ${DIM}access logs -n50${NC}                            # Show last 50 log entries"
        echo "    ${DIM}access clean${NC}                                # Clean temporary files and locks"
        echo ""
        echo "${BOLD}Environment variables:${NC}"
        echo "${BOLD}---------------------${NC}"
        echo "    ${YELLOW}ACCESS_PROVIDER${NC}   DNS provider"
        echo "    ${YELLOW}ACCESS_DOMAIN${NC}     Domain to update"
        echo "    ${YELLOW}ACCESS_HOST${NC}       Host record (default: @)"
        echo "    ${YELLOW}ACCESS_INTERVAL${NC}   Update interval in seconds (default: 300)"
        echo ""
        echo "${DIM}Access v$VERSION - Pure shell DNS synchronization with auto-discovery${NC}"
        echo ""
        ;;
esac
