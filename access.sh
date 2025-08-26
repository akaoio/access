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
ACCESS_HOME="${ACCESS_HOME:-$HOME/.access}"
ACCESS_CONFIG="${ACCESS_CONFIG:-$ACCESS_HOME/config.json}"
ACCESS_STATE="${ACCESS_STATE:-$ACCESS_HOME/state.json}"
ACCESS_LOG="${ACCESS_LOG:-$ACCESS_HOME/access.log}"

# Get script directory for provider loading
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure access directory exists
mkdir -p "$ACCESS_HOME"

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

# IP validation
validate_ip() {
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

# Detect public IP via DNS
detect_ip_dns() {
    local ip=""
    
    # Try OpenDNS
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -n1)
        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Try nslookup
    if command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup myip.opendns.com resolver1.opendns.com 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    return 1
}

# Detect public IP via HTTP
detect_ip_http() {
    local ip=""
    local services="https://checkip.amazonaws.com https://ipv4.icanhazip.com https://ifconfig.me"
    
    for service in $services; do
        # Try curl
        if command -v curl >/dev/null 2>&1; then
            ip=$(curl -s --max-time 5 "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
            if validate_ip "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
        
        # Try wget
        if command -v wget >/dev/null 2>&1; then
            ip=$(wget -qO- --timeout=5 "$service" 2>/dev/null | tr -d '\n\r' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
            if validate_ip "$ip"; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    return 1
}

# Main IP detection
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
            
            # Export provider-specific fields
            jq -r ".[\"$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')\"] // {} | to_entries | .[] | \"${prefix}_\\(.key | ascii_upcase)=\\(.value)\"" "$ACCESS_CONFIG" 2>/dev/null | while IFS='=' read -r key value; do
                export "$key=$value"
            done
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
            field_name=$(echo "$env_var" | sed "s/^${provider_upper}_//" | tr '[:upper:]' '[:lower:]')
            
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

# Auto-update function
auto_update() {
    log "Checking for updates..."
    
    local CURRENT="$0"
    local TEMP=$(mktemp /tmp/access_update.XXXXXX 2>/dev/null || echo "/tmp/access_update_$$")
    local UPDATE_URL="https://raw.githubusercontent.com/akaoio/access/main/access.sh"
    
    # Download latest version
    if command -v curl >/dev/null 2>&1; then
        curl -sSL "$UPDATE_URL" -o "$TEMP" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$UPDATE_URL" -O "$TEMP" 2>/dev/null
    else
        log "Cannot check for updates (no curl/wget)"
        return 1
    fi
    
    if [ -f "$TEMP" ] && [ -s "$TEMP" ]; then
        # Check if update needed
        if ! cmp -s "$TEMP" "$CURRENT" 2>/dev/null; then
            # Backup current version
            cp "$CURRENT" "$CURRENT.backup"
            
            # Check if we can write
            if [ -w "$CURRENT" ]; then
                cp "$TEMP" "$CURRENT"
                chmod +x "$CURRENT"
            else
                # Try with sudo
                if command -v sudo >/dev/null 2>&1; then
                    sudo cp "$TEMP" "$CURRENT"
                    sudo chmod +x "$CURRENT"
                else
                    log "Cannot update: no write permission"
                    rm -f "$TEMP"
                    return 1
                fi
            fi
            
            log "✓ Updated to latest version"
            rm -f "$TEMP"
            
            # Re-execute with original arguments
            exec "$CURRENT" "$@"
        else
            log "Already running latest version"
        fi
    else
        log "Failed to download update"
    fi
    
    rm -f "$TEMP"
    return 0
}

# Main command handler
case "${1:-help}" in
    ip)
        ip=$(detect_ip)
        if [ $? -eq 0 ]; then
            log_success "Detected IP: $ip"
            echo "$ip"
        else
            log_error "Failed to detect IP"
            exit 1
        fi
        ;;
        
    update)
        # Check for updates first (optional)
        if [ "${AUTO_UPDATE:-false}" = "true" ]; then
            auto_update "$@"
        fi
        
        load_config
        
        if [ -z "$PROVIDER" ]; then
            log_error "No provider configured"
            log_info "Run: access config <provider> --help"
            exit 1
        fi
        
        ip=$(detect_ip)
        if [ $? -ne 0 ]; then
            log_error "Failed to detect IP"
            exit 1
        fi
        
        log_success "Detected IP: $ip"
        log_info "Using provider: $PROVIDER"
        
        # Use provider abstraction to update DNS
        update_with_provider "$PROVIDER" "$DOMAIN" "$HOST" "$ip"
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
        log "Starting Access daemon..."
        while true; do
            "$0" update
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
        
    auto-update)
        auto_update "$@"
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
        echo "    ${BLUE}access ip${NC}              Detect and display public IP"
        echo "    ${BLUE}access update${NC}          Update DNS with current IP"  
        echo "    ${BLUE}access config${NC}          Configure DNS provider"
        echo "    ${BLUE}access providers${NC}       List available providers"
        echo "    ${BLUE}access discover${NC}        Auto-discover all providers"
        echo "    ${BLUE}access capabilities${NC}    Show provider capabilities"
        echo "    ${BLUE}access suggest${NC}         Suggest provider for domain"
        echo "    ${BLUE}access health${NC}          Check provider health"
        echo "    ${BLUE}access test${NC} [provider] Test provider connectivity"
        echo "    ${BLUE}access daemon${NC}          Run as daemon (updates every 5 minutes)"
        echo "    ${BLUE}access auto-update${NC}     Check and install updates"
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
        echo "    ${YELLOW}AUTO_UPDATE${NC}       Enable auto-updates on 'update' command (true/false)"
        echo ""
        echo "${DIM}Note: v$VERSION - Humble beginnings with auto-agnostic provider discovery${NC}"
        echo ""
        ;;
esac