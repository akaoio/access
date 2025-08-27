#!/bin/sh
# Access - Pure shell network access layer with modular provider support
# The eternal foundation that enables connectivity

VERSION="0.0.2"

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

log_warning() {
    echo "${YELLOW}⚠ Warning:${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" >> "$ACCESS_LOG"
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

# Legacy path for migration
ACCESS_LEGACY_HOME="$HOME/.access"

# Get script directory for provider loading
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure XDG-compliant directories exist
mkdir -p "$ACCESS_CONFIG_HOME"
mkdir -p "$ACCESS_DATA_HOME"

# Migration: Move existing config from legacy location to XDG
migrate_legacy_config() {
    if [ -d "$ACCESS_LEGACY_HOME" ] && [ ! -f "$ACCESS_CONFIG" ] && [ -f "$ACCESS_LEGACY_HOME/config.json" ]; then
        log_debug "Migrating configuration from legacy location to XDG-compliant paths"
        
        # Migrate config file
        if [ -f "$ACCESS_LEGACY_HOME/config.json" ]; then
            cp "$ACCESS_LEGACY_HOME/config.json" "$ACCESS_CONFIG"
            log "✓ Migrated config: ~/.access/config.json → ~/.config/access/config.json"
        fi
        
        # Migrate log file 
        if [ -f "$ACCESS_LEGACY_HOME/access.log" ]; then
            cp "$ACCESS_LEGACY_HOME/access.log" "$ACCESS_LOG"
            log "✓ Migrated log: ~/.access/access.log → ~/.local/share/access/access.log"
        fi
        
        # Migrate state file
        if [ -f "$ACCESS_LEGACY_HOME/state.json" ]; then
            cp "$ACCESS_LEGACY_HOME/state.json" "$ACCESS_STATE"
            log "✓ Migrated state: ~/.access/state.json → ~/.local/share/access/state.json"
        fi
        
        # Migrate last_run file
        if [ -f "$ACCESS_LEGACY_HOME/last_run" ]; then
            cp "$ACCESS_LEGACY_HOME/last_run" "$ACCESS_DATA_HOME/last_run"
            log "✓ Migrated last_run file to XDG data directory"
        fi
        
        log "📁 Configuration migrated to XDG Base Directory Specification"
        log "   Config: $ACCESS_CONFIG"
        log "   Data: $ACCESS_DATA_HOME"
        log ""
        log "Legacy directory ~/.access can be safely removed after verification"
    fi
}

# Run migration check
migrate_legacy_config

# Source provider abstraction layer (prefer agnostic version)
if [ -f "$SCRIPT_DIR/provider-agnostic.sh" ]; then
    . "$SCRIPT_DIR/provider-agnostic.sh"
elif [ -f "$SCRIPT_DIR/provider.sh" ]; then
    . "$SCRIPT_DIR/provider.sh"
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

# IP validation (IPv4 or IPv6)
validate_ip() {
    local ip="$1"
    validate_ipv4 "$ip" || validate_ipv6 "$ip"
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
            ip=$(curl -s -6 --max-time 5 "$service" 2>/dev/null | tr -d '\n\r' | head -n1)
            if validate_ipv6 "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Try wget with IPv6
        if command -v wget >/dev/null 2>&1; then
            ip=$(wget -qO- -6 --timeout=5 "$service" 2>/dev/null | tr -d '\n\r' | head -n1)
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
            ip=$(curl -s -4 --max-time 5 "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
            if validate_ipv4 "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Try wget
        if command -v wget >/dev/null 2>&1; then
            ip=$(wget -qO- -4 --timeout=5 "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
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
        HOST=$(jq -r '.host // "@"' "$ACCESS_CONFIG")
        
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
    
    printf "%b\n" "$config_json" > "$ACCESS_CONFIG"
    log "Configuration saved to $ACCESS_CONFIG"
    log "Provider: $provider, Domain: $DOMAIN, Host: $HOST"
}

# Self-update using Manager framework
self_update() {
    log "Checking for updates using Manager framework..."
    
    # Check if Manager is available
    if [ -f "$HOME/manager/manager-self-update.sh" ]; then
        . "$HOME/manager/manager-self-update.sh"
        manager_self_update "access" "https://github.com/akaoio/access.git" || {
            log "Update failed"
            return 1
        }
    elif [ -f "/usr/local/lib/manager/manager-self-update.sh" ]; then
        . "/usr/local/lib/manager/manager-self-update.sh"
        manager_self_update "access" "https://github.com/akaoio/access.git" || {
            log "Update failed"
            return 1
        }
    else
        log "Manager framework not installed. Run install.sh first."
        return 1
    fi
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
        echo "    ${BLUE}access ip${NC}              Detect public IP (IPv6 priority)"
        echo "    ${BLUE}access ipv4${NC}            Force IPv4 detection only"
        echo "    ${BLUE}access ipv6${NC}            Force IPv6 detection only"
        echo "    ${BLUE}access update${NC}          Update DNS with current IP"  
        echo "    ${BLUE}access config${NC}          Configure DNS provider"
        echo "    ${BLUE}access providers${NC}       List available providers"
        echo "    ${BLUE}access discover${NC}        Auto-discover all providers"
        echo "    ${BLUE}access capabilities${NC}    Show provider capabilities"
        echo "    ${BLUE}access suggest${NC}         Suggest provider for domain"
        echo "    ${BLUE}access health${NC}          Check provider health"
        echo "    ${BLUE}access test${NC} [provider] Test provider connectivity"
        echo "    ${BLUE}access daemon${NC}          Run as daemon (updates every 5 minutes)"
        echo "    ${BLUE}access self-update${NC}     Update using Manager framework"
        echo "    ${BLUE}access version${NC}         Show version"
        echo "    ${BLUE}access help${NC}            Show this help"
        echo ""
        echo "${BOLD}Configuration:${NC}"
        echo "${BOLD}-------------${NC}"
        echo "    ${YELLOW}access config${NC} <provider> ${DIM}--help${NC}     Show provider configuration help"
        echo "    ${YELLOW}access config${NC} <provider> ${DIM}[options]${NC}  Configure provider"
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
        echo "    ${DIM}access config godaddy --domain=example.com --key=KEY --secret=SECRET${NC}"
        echo "    ${DIM}access config cloudflare --domain=example.com --email=EMAIL --api-key=KEY --zone-id=ZONE${NC}"
        echo "    ${DIM}access config azure --domain=example.com --subscription-id=ID --resource-group=RG${NC}"
        echo "    ${DIM}access config gcloud --domain=example.com --project-id=PROJECT --zone-name=ZONE${NC}"
        echo ""
        echo "${BOLD}Environment variables:${NC}"
        echo "${BOLD}---------------------${NC}"
        echo "    ${YELLOW}ACCESS_HOME${NC}       Config directory (default: ~/.access)"
        echo "    ${YELLOW}ACCESS_PROVIDER${NC}   DNS provider"
        echo "    ${YELLOW}ACCESS_DOMAIN${NC}     Domain to update"
        echo "    ${YELLOW}ACCESS_HOST${NC}       Host record (default: @)"
        echo "    ${YELLOW}ACCESS_INTERVAL${NC}   Update interval in seconds (default: 300)"
        # AUTO_UPDATE environment variable removed - managed by Manager framework"
        echo ""
        echo "${DIM}Note: v$VERSION - Humble beginnings with auto-agnostic provider discovery${NC}"
        echo ""
        ;;
esac