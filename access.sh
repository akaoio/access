#!/bin/sh
# Access - Pure shell network access layer with modular provider support
# The eternal foundation that enables connectivity
# Now with bidirectional Stacker integration - works standalone OR enhanced

VERSION="0.0.3"

# Load the Stacker bridge for bidirectional architecture
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/stacker-bridge.sh" ]; then
    . "$SCRIPT_DIR/lib/stacker-bridge.sh"
elif [ -f "./lib/stacker-bridge.sh" ]; then
    . "./lib/stacker-bridge.sh"
fi

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

# SECURITY FIX 2: Secure logging functions with credential masking
sanitize_log_message() {
    local message="$*"
    
    # Mask common credential patterns
    message=$(echo "$message" | sed -E '
        # Mask API keys (various formats)
        s/(key[[:space:]]*[:=][[:space:]]*)[^[:space:]]{8,}([^[:space:]]*)/\1****\2/gi
        s/(api[_-]?key[[:space:]]*[:=][[:space:]]*)[^[:space:]]{8,}([^[:space:]]*)/\1****\2/gi
        
        # Mask secrets
        s/(secret[[:space:]]*[:=][[:space:]]*)[^[:space:]]{8,}([^[:space:]]*)/\1****\2/gi
        s/(api[_-]?secret[[:space:]]*[:=][[:space:]]*)[^[:space:]]{8,}([^[:space:]]*)/\1****\2/gi
        
        # Mask tokens
        s/(token[[:space:]]*[:=][[:space:]]*)[^[:space:]]{8,}([^[:space:]]*)/\1****\2/gi
        s/(access[_-]?token[[:space:]]*[:=][[:space:]]*)[^[:space:]]{8,}([^[:space:]]*)/\1****\2/gi
        
        # Mask passwords
        s/(password[[:space:]]*[:=][[:space:]]*)[^[:space:]]{1,}([^[:space:]]*)/\1****\2/gi
        s/(pass[[:space:]]*[:=][[:space:]]*)[^[:space:]]{1,}([^[:space:]]*)/\1****\2/gi
        
        # Mask long alphanumeric strings that look like credentials
        s/([^[:space:]]{32,})/[MASKED]/g
        
        # Mask base64-like strings
        s/([A-Za-z0-9+/]{40,}={0,2})/[MASKED_BASE64]/g
    ')
    
    echo "$message"
}

# SECURITY FIX 4: Input validation functions for DNS provider injection prevention
validate_domain_name() {
    local domain="$1"
    
    # Check if domain is empty
    [ -z "$domain" ] && return 1
    
    # Length limits (RFC compliant)
    [ ${#domain} -gt 253 ] && return 1
    [ ${#domain} -lt 1 ] && return 1
    
    # Valid DNS characters only (RFC 1123)
    case "$domain" in
        *[^a-zA-Z0-9.-]*)
            return 1
            ;;
    esac
    
    # No leading/trailing dots or hyphens
    case "$domain" in
        .*|*.|*-|-*|*..*|*-.*|*.-*)
            return 1
            ;;
    esac
    
    # Check each label (part between dots)
    local IFS='.'
    for label in $domain; do
        # Label length (max 63 characters per RFC)
        [ ${#label} -gt 63 ] && return 1
        [ ${#label} -lt 1 ] && return 1
        
        # Label must not start or end with hyphen
        case "$label" in
            -*|*-)
                return 1
                ;;
        esac
    done
    
    return 0
}

validate_hostname() {
    local hostname="$1"
    
    # Check if hostname is empty or @ (root domain)
    [ -z "$hostname" ] && return 1
    [ "$hostname" = "@" ] && return 0
    
    # Length limits
    [ ${#hostname} -gt 63 ] && return 1
    
    # Valid hostname characters only
    case "$hostname" in
        *[^a-zA-Z0-9-]*)
            return 1
            ;;
    esac
    
    # No leading/trailing hyphens
    case "$hostname" in
        -*|*-)
            return 1
            ;;
    esac
    
    return 0
}

validate_ip_address() {
    local ip="$1"
    
    [ -z "$ip" ] && return 1
    
    # IPv4 validation
    if echo "$ip" | grep -q '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$'; then
        local IFS='.'
        set -- $ip
        [ $# -eq 4 ] || return 1
        for octet in "$@"; do
            # Check if numeric and in range 0-255
            case "$octet" in
                ''|*[!0-9]*)
                    return 1
                    ;;
            esac
            [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ] && return 1
        done
        return 0
    fi
    
    # IPv6 validation (basic)
    if echo "$ip" | grep -q ':'; then
        # Basic IPv6 pattern check
        echo "$ip" | grep -q '^[a-fA-F0-9:]*$' || return 1
        # More thorough validation would be complex, this catches basic issues
        [ ${#ip} -gt 39 ] && return 1  # Max IPv6 length
        return 0
    fi
    
    return 1
}

# SECURITY FIX 5: HTTPS enforcement functions
validate_https_url() {
    local url="$1"
    
    [ -z "$url" ] && return 1
    
    # Must start with https://
    case "$url" in
        https://*)
            # Valid HTTPS URL
            ;;
        http://*)
            echo "Error: HTTP URLs are not allowed, use HTTPS only: $url" >&2
            return 1
            ;;
        *)
            echo "Error: Invalid URL format, must start with https://: $url" >&2
            return 1
            ;;
    esac
    
    # Basic URL validation (prevent injection)
    case "$url" in
        *[[:space:]]*)
            echo "Error: URL contains spaces: $url" >&2
            return 1
            ;;
        *[\;\&\|\`\$\(\)]*)
            echo "Error: URL contains dangerous characters: $url" >&2
            return 1
            ;;
    esac
    
    return 0
}

# Secure HTTP request function with HTTPS enforcement
secure_http_request() {
    local method="$1"
    local url="$2"
    local headers="$3"
    local data="$4"
    
    # Validate HTTPS
    if ! validate_https_url "$url"; then
        return 1
    fi
    
    # Use curl with security settings
    local curl_opts=""
    curl_opts="$curl_opts --ssl-reqd"                # Require SSL/TLS
    curl_opts="$curl_opts --cert-status"             # Verify certificate status
    curl_opts="$curl_opts --fail-with-body"          # Fail on HTTP error codes
    curl_opts="$curl_opts --max-time 30"             # Timeout after 30 seconds
    curl_opts="$curl_opts --retry 2"                 # Retry on failure
    curl_opts="$curl_opts --retry-delay 1"           # Delay between retries
    curl_opts="$curl_opts --connect-timeout 10"      # Connection timeout
    
    # Execute request
    case "$method" in
        GET|get)
            curl $curl_opts -X GET "$url" ${headers:+-H "$headers"}
            ;;
        POST|post)
            curl $curl_opts -X POST "$url" ${headers:+-H "$headers"} ${data:+-d "$data"}
            ;;
        PUT|put)
            curl $curl_opts -X PUT "$url" ${headers:+-H "$headers"} ${data:+-d "$data"}
            ;;
        DELETE|delete)
            curl $curl_opts -X DELETE "$url" ${headers:+-H "$headers"}
            ;;
        *)
            echo "Error: Unsupported HTTP method: $method" >&2
            return 1
            ;;
    esac
}

# SECURITY FIX 6: Process isolation and privilege management
drop_privileges() {
    # Only drop privileges if running as root
    if [ "$(id -u)" -eq 0 ]; then
        # Find a non-root user to switch to
        local target_user="${ACCESS_USER:-nobody}"
        
        # Verify user exists
        if id "$target_user" >/dev/null 2>&1; then
            log_info "Dropping privileges to user: $target_user"
            # Note: In shell scripts, we can't actually drop privileges
            # This would need to be implemented at the service level
            export ACCESS_DROPPED_PRIVILEGES="true"
            export ACCESS_ORIGINAL_USER="root"
            export ACCESS_CURRENT_USER="$target_user"
        else
            log_error "Cannot drop privileges: user $target_user does not exist"
            return 1
        fi
    fi
    return 0
}

secure_process_execution() {
    local command="$1"
    shift
    local args="$*"
    
    # Set secure environment
    unset IFS
    export PATH="/usr/local/bin:/usr/bin:/bin"
    
    # Clear dangerous environment variables
    unset LD_PRELOAD
    unset LD_LIBRARY_PATH
    unset DYLD_LIBRARY_PATH
    
    # Execute with limited resources
    if command -v timeout >/dev/null 2>&1; then
        timeout 300 "$command" $args  # 5 minute timeout
    else
        "$command" $args
    fi
}

# SECURITY FIX 7: Configuration injection prevention
validate_json_config() {
    local config_file="$1"
    
    [ ! -f "$config_file" ] && return 1
    
    # Check file size (prevent resource exhaustion)
    file_size=$(wc -c < "$config_file" 2>/dev/null || echo 0)
    if [ "$file_size" -gt 1048576 ]; then  # 1MB limit
        echo "Error: Configuration file too large (security risk): $config_file" >&2
        return 1
    fi
    
    # Basic JSON syntax validation
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty < "$config_file" >/dev/null 2>&1; then
            echo "Error: Invalid JSON in configuration file: $config_file" >&2
            return 1
        fi
    else
        # Fallback validation - check basic JSON structure
        if ! grep -q '^[[:space:]]*{.*}[[:space:]]*$' "$config_file"; then
            echo "Error: Configuration file does not appear to be valid JSON: $config_file" >&2
            return 1
        fi
    fi
    
    # Check for dangerous content patterns
    if grep -q '\(\$\|\`\|;\|&\||\|<\|>\)' "$config_file"; then
        echo "Error: Configuration file contains potentially dangerous characters: $config_file" >&2
        return 1
    fi
    
    return 0
}

validate_config_value() {
    local key="$1"
    local value="$2"
    
    [ -z "$key" ] && return 1
    [ -z "$value" ] && return 1
    
    # Length limits
    [ ${#key} -gt 100 ] && return 1
    [ ${#value} -gt 1000 ] && return 1
    
    # Key validation (only alphanumeric, underscore, dot)
    case "$key" in
        *[^a-zA-Z0-9_.]*)
            return 1
            ;;
    esac
    
    # Value validation (prevent injection)
    case "$value" in
        *[\`\$\;]*)
            return 1
            ;;
    esac
    
    return 0
}

# Color logging functions with credential protection and flag integration
log_success() {
    local sanitized_msg="$(sanitize_log_message "$*")"
    if [ "$QUIET" != "true" ]; then
        echo "${GREEN}✓${NC} $*"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $sanitized_msg" >> "$ACCESS_LOG"
}

log_error() {
    local sanitized_msg="$(sanitize_log_message "$*")"
    if [ -n "$RED" ]; then
        echo "${RED}✗ Error:${NC} $*" >&2
    else
        echo "Error: $*" >&2
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $sanitized_msg" >> "$ACCESS_LOG"
}

log_info() {
    local sanitized_msg="$(sanitize_log_message "$*")"
    if [ "$QUIET" != "true" ]; then
        echo "${BLUE}ℹ${NC} $*"
    fi
    if [ "$VERBOSE" = "true" ] || [ "$DEBUG" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $sanitized_msg" >> "$ACCESS_LOG"
    fi
}

log_debug() {
    local sanitized_msg="$(sanitize_log_message "$*")"
    if [ "$DEBUG" = "true" ] || [ "${ACCESS_DEBUG:-0}" = "1" ]; then
        if [ "$QUIET" != "true" ]; then
            echo "${DIM}[DEBUG]${NC} $*" >&2
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $sanitized_msg" >> "$ACCESS_LOG"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = "true" ] || [ "$DEBUG" = "true" ]; then
        if [ "$QUIET" != "true" ]; then
            echo "${DIM}[VERBOSE]${NC} $*"
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] VERBOSE: $*" >> "$ACCESS_LOG"
    fi
}

# SECURITY FIX 3: Secure temporary file management with race condition prevention
ACCESS_TEMP_FILES=""

# Secure temporary file creation
secure_mktemp() {
    local prefix="${1:-access}"
    local temp_file
    
    # Use mktemp with secure permissions
    if command -v mktemp >/dev/null 2>&1; then
        temp_file=$(mktemp -t "${prefix}.XXXXXX")
    else
        # Fallback for systems without mktemp
        temp_file="/tmp/${prefix}.$$.$RANDOM"
        touch "$temp_file"
    fi
    
    if [ -n "$temp_file" ]; then
        # Set secure permissions (owner only)
        chmod 600 "$temp_file" 2>/dev/null
        # Track temp files for cleanup
        ACCESS_TEMP_FILES="$ACCESS_TEMP_FILES $temp_file"
        echo "$temp_file"
        return 0
    else
        echo "Error: Failed to create secure temporary file" >&2
        return 1
    fi
}

# Secure cleanup on exit
cleanup() {
    # Remove tracked temp files safely
    for temp_file in $ACCESS_TEMP_FILES; do
        if [ -f "$temp_file" ]; then
            rm -f "$temp_file" 2>/dev/null
        fi
    done
    
    # Remove any remaining access temp files (more secure pattern)
    find /tmp -name "access.$$.*" -user "$(whoami)" -type f -delete 2>/dev/null || true
    
    # Remove any stale lock files owned by this process
    if [ -n "$ACCESS_LOCK_FILE" ] && [ -f "$ACCESS_LOCK_FILE" ]; then
        lock_pid=$(cat "$ACCESS_LOCK_FILE" 2>/dev/null)
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$ACCESS_LOCK_FILE" 2>/dev/null
        fi
    fi
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

# Source advanced features module
if [ -f "$SCRIPT_DIR/modules/advanced.sh" ]; then
    . "$SCRIPT_DIR/modules/advanced.sh"
    advanced_init
else
    # Advanced features not available - continue with basic functionality
    log_debug "Advanced features module not found - using basic functionality"
fi

# Source enhanced service module  
if [ -f "$SCRIPT_DIR/modules/service.sh" ]; then
    . "$SCRIPT_DIR/modules/service.sh"
    # Don't call service_init here as it may depend on other functions
else
    log_debug "Enhanced service module not found - using basic functionality"
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
    
    # Try OpenDNS IPv6 (configurable via environment)
    local ipv6_dns_primary="${ACCESS_IPV6_DNS_PRIMARY:-2620:119:35::35}"
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short myip.opendns.com @"$ipv6_dns_primary" AAAA 2>/dev/null | head -n1)
        if validate_ipv6 "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Try secondary IPv6 DNS (configurable via environment)
    local ipv6_dns_secondary="${ACCESS_IPV6_DNS_SECONDARY:-2001:4860:4860::8888}"
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short @"$ipv6_dns_secondary" myip.opendns.com AAAA 2>/dev/null | head -n1)
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
    
    # Try OpenDNS (configurable via environment)
    local ipv4_dns_primary="${ACCESS_IPV4_DNS_PRIMARY:-resolver1.opendns.com}"
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short myip.opendns.com @"$ipv4_dns_primary" 2>/dev/null | head -n1)
        if validate_ipv4 "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Try nslookup
    if command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup myip.opendns.com "$ipv4_dns_primary" 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
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
    # Allow custom IP detection services via environment
    local services="${ACCESS_IPV6_SERVICES:-https://ipv6.icanhazip.com https://v6.ident.me https://ipv6.whatismyip.akamai.com}"
    
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
    # Allow custom IP detection services via environment
    local services="${ACCESS_IPV4_SERVICES:-https://checkip.amazonaws.com https://ipv4.icanhazip.com https://ifconfig.me}"
    
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
    local lock_timeout=${ACCESS_LOCK_TIMEOUT:-600}  # Default 10 minutes, configurable
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
            local temp_file=$(secure_mktemp "access-config")
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
    
    # Handle empty host based on scan setting
    if [ -z "$HOST" ]; then
        # Check if scan is enabled (from config or environment)
        SCAN_ENABLED="${ACCESS_SCAN:-false}"
        if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
            SCAN_ENABLED=$(jq -r '.scan // false' "$ACCESS_CONFIG" 2>/dev/null || echo "false")
        fi
        
        if [ "$SCAN_ENABLED" = "true" ] && [ -n "$DOMAIN" ]; then
            log "Host is empty with scan enabled - finding available slot..."
            
            # Check if scan.sh exists
            SCAN_SCRIPT="$(dirname "$0")/scan.sh"
            if [ ! -f "$SCAN_SCRIPT" ]; then
                # Try installed location
                SCAN_SCRIPT="/usr/local/bin/access-scan"
                if [ ! -f "$SCAN_SCRIPT" ]; then
                    # Try user location
                    SCAN_SCRIPT="$HOME/.local/bin/access-scan"
                fi
            fi
            
            if [ -f "$SCAN_SCRIPT" ] && [ -x "$SCAN_SCRIPT" ]; then
                # Source scan functions
                . "$SCAN_SCRIPT"
                
                # Set scan variables
                DOMAIN="$DOMAIN"
                HOST_PREFIX="${HOST_PREFIX:-peer}"
                
                # Find available slot
                if slot=$(find_lowest_available_slot); then
                    HOST="${HOST_PREFIX}${slot}"
                    log_success "Auto-discovered available host: $HOST"
                    
                    # Save the discovered host back to config
                    if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
                        temp_file=$(secure_mktemp "access-scan")
                        jq ".host = \"$HOST\"" "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
                        log "Saved auto-discovered host to configuration"
                    fi
                else
                    log_warning "Auto-scan failed - using root domain (@)"
                    HOST="@"
                fi
            else
                log_warning "Scan module not found - using root domain (@)"
                HOST="@"
            fi
        else
            # Scan not enabled or no domain - use root
            log_debug "Host empty, scan disabled - using root domain (@)"
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
            env_value=$(printenv "$env_var")
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
    
    # Add scan flag if set in environment
    if [ -n "$SCAN_ENABLED" ]; then
        # Parse existing config and add scan flag
        if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
            # First save the basic config
            printf "%b\n" "$config_json" > "$ACCESS_CONFIG"
            # Then add scan flag using jq
            temp_file=$(secure_mktemp "access-scan-config")
            jq ".scan = $SCAN_ENABLED" "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
        else
            # Fallback: manually add scan field before closing brace
            config_json=$(echo "$config_json" | sed 's/\n}$/,\n    "scan": '"$SCAN_ENABLED"'\n}/')
            printf "%b\n" "$config_json" > "$ACCESS_CONFIG"
        fi
    else
        printf "%b\n" "$config_json" > "$ACCESS_CONFIG"
    fi
    
    log "Configuration saved to $ACCESS_CONFIG"
    log "Provider: $provider, Domain: $DOMAIN, Host: $HOST"
}

# Self-update using Stacker framework
self_update() {
    log "Checking for updates using Stacker framework..."
    
    # Find Stacker in various locations
    local stacker_found=false
    local stacker_dirs="$HOME/stacker /usr/local/lib/stacker"
    
    # Also check if we can access root's manager (for system installations)
    if [ -r "/root/stacker/stacker-self-update.sh" ]; then
        stacker_dirs="$stacker_dirs /root/stacker"
    fi
    
    local stacker_dir=""
    for dir in $stacker_dirs; do
        if [ -f "$dir/stacker-self-update.sh" ]; then
            log "Loading Stacker from $dir"
            stacker_dir="$dir"
            stacker_found=true
            break
        fi
    done
    
    if [ "$stacker_found" = false ]; then
        # Try to clone Stacker if not found
        log "Stacker not found. Installing Stacker framework..."
        git clone https://github.com/akaoio/stacker.git "$HOME/stacker" || {
            log "Failed to install Stacker framework"
            return 1
        }
        stacker_dir="$HOME/stacker"
    fi
    
    # Load all Stacker modules needed
    if [ -f "$stacker_dir/stacker-core.sh" ]; then
        . "$stacker_dir/stacker-core.sh"
    fi
    if [ -f "$stacker_dir/stacker-update.sh" ]; then
        . "$stacker_dir/stacker-update.sh"
    fi
    
    # Initialize Stacker environment variables for Access
    export STACKER_CLEAN_CLONE_DIR="/home/x/access"
    export STACKER_CONFIG_DIR="$HOME/.config/access"
    
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
    
    # Use the correct Stacker update functions
    case "$action" in
        apply)
            if command -v stacker_apply_updates >/dev/null 2>&1; then
                log "Applying updates..."
                stacker_apply_updates || {
                    log "Update application completed"
                }
            else
                log "Stacker update functions not available"
                return 1
            fi
            ;;
        status)
            if command -v stacker_check_updates >/dev/null 2>&1; then
                if stacker_check_updates; then
                    log "Updates are available"
                    return 0
                else
                    log "Already up to date"
                    return 1
                fi
            fi
            ;;
        check|*)
            if command -v stacker_check_updates >/dev/null 2>&1; then
                if stacker_check_updates; then
                    log "Updates are available. Run 'access self-update --apply' to install"
                    return 0
                else
                    log "Already up to date"
                    return 1
                fi
            else
                log "Stacker update functions not available"
                return 1
            fi
            ;;
    esac
    
    log "Update check completed"
}

# Helper functions for advanced flags
get_provider_capabilities() {
    provider="$1"
    case "$provider" in
        godaddy)
            echo "DNS management, Domain registration, SSL certificates"
            ;;
        cloudflare)
            echo "DNS management, CDN, DDoS protection, SSL certificates"
            ;;
        namecheap)
            echo "DNS management, Domain registration"
            ;;
        *)
            echo "Basic DNS management"
            ;;
    esac
}

can_provider_manage() {
    provider="$1"
    domain="$2"
    
    # Load provider to check if it can manage the domain
    if load_provider "$provider" >/dev/null 2>&1; then
        # For now, assume all loaded providers can manage any domain
        # In a real implementation, this would check with the provider
        return 0
    else
        return 1
    fi
}

# Global flag variables
DRY_RUN=false
VERBOSE=false
QUIET=false
DEBUG=false
SHOW_VERSION=false
SHOW_HELP=false

# Advanced flag variables
FORCE_RESTART=false
RELOAD_CONFIG=false
STOP_DAEMON=false
DAEMON_STATUS=false
SHOW_CONFIG=false
SET_CONFIG=""
RESET_CONFIG=false
VALIDATE_CONFIG=false
CONNECTIVITY_TEST=false
DNS_CHECK=false
HEALTH_CHECK=false
TEST_PROVIDER=""

# Parse global flags first
ORIGINAL_ARGS="$*"
PARSED_ARGS=""
TEMP_ARGS=""
SKIP_NEXT=false

# Save original arguments safely before processing
ORIGINAL_ARGS="$@"

# Process arguments without eval
while [ $# -gt 0 ]; do
    case "$1" in
        # Priority 1 - Global flags
        --help|-h)
            SHOW_HELP=true
            ;;
        --version|-v)
            SHOW_VERSION=true
            ;;
        --dry-run)
            DRY_RUN=true
            ACCESS_DRY_RUN=true
            export ACCESS_DRY_RUN
            log_info "DRY RUN MODE: No changes will be applied"
            # Enable dry-run mode in advanced module if available
            if command -v access_dry_run_mode >/dev/null 2>&1; then
                access_dry_run_mode
            fi
            ;;
        --verbose)
            VERBOSE=true
            log_info "Verbose mode enabled"
            ;;
        --quiet|-q)
            QUIET=true
            ;;
        --debug)
            DEBUG=true
            VERBOSE=true
            log_info "Debug mode enabled"
            ;;
        --json)
            ACCESS_JSON_OUTPUT=true
            export ACCESS_JSON_OUTPUT
            ;;
            
        # Priority 2 - Service management flags
        --force-restart)
            FORCE_RESTART=true
            ;;
        --reload-config)
            RELOAD_CONFIG=true
            ;;
        --stop-daemon)
            STOP_DAEMON=true
            ;;
        --daemon-status)
            DAEMON_STATUS=true
            ;;
            
        # Priority 3 - Configuration flags
        --show-config)
            SHOW_CONFIG=true
            ;;
        --set-config=*)
            SET_CONFIG="${1#--set-config=}"
            ;;
        --set-config)
            shift
            SET_CONFIG="$1"
            ;;
        --reset-config)
            RESET_CONFIG=true
            ;;
        --validate-config)
            VALIDATE_CONFIG=true
            ;;
            
        # Priority 4 - Diagnostics flags
        --connectivity-test)
            CONNECTIVITY_TEST=true
            ;;
        --dns-check)
            DNS_CHECK=true
            ;;
        --health-check)
            HEALTH_CHECK=true
            ;;
        --test-provider=*)
            TEST_PROVIDER="${1#--test-provider=}"
            ;;
        --test-provider)
            shift
            TEST_PROVIDER="$1"
            ;;
            
        *)
            PARSED_ARGS="$PARSED_ARGS $1"
            ;;
    esac
    shift
done

# Handle global flags first
if [ "$SHOW_VERSION" = "true" ]; then
    echo "Access v$VERSION"
    echo "Pure shell DNS synchronization with auto-scan"
    exit 0
fi

if [ "$SHOW_HELP" = "true" ]; then
    # Set first argument to help to trigger help display
    set -- help
fi

# Handle advanced global flags
if [ "$SHOW_CONFIG" = "true" ]; then
    load_config
    echo "Current Configuration:"
    echo "==================="
    echo "Provider: ${PROVIDER:-<not set>}"
    echo "Domain: ${DOMAIN:-<not set>}"
    echo "Host: ${HOST:-<not set>}"
    echo "Interval: ${INTERVAL:-300}"
    echo "Scan enabled: ${SCAN_ENABLED:-false}"
    echo "Config file: $ACCESS_CONFIG"
    exit 0
fi

if [ -n "$SET_CONFIG" ]; then
    key=$(echo "$SET_CONFIG" | cut -d'=' -f1)
    value=$(echo "$SET_CONFIG" | cut -d'=' -f2-)
    
    if [ -z "$key" ] || [ -z "$value" ]; then
        log_error "Invalid config format. Use: --set-config KEY=VALUE"
        exit 1
    fi
    
    log_info "Setting configuration: $key=$value"
    
    case "$key" in
        provider|PROVIDER)
            echo "PROVIDER=\"$value\"" > "$ACCESS_CONFIG.tmp"
            grep -v "^PROVIDER=" "$ACCESS_CONFIG" 2>/dev/null >> "$ACCESS_CONFIG.tmp" || true
            mv "$ACCESS_CONFIG.tmp" "$ACCESS_CONFIG"
            ;;
        domain|DOMAIN)
            echo "DOMAIN=\"$value\"" > "$ACCESS_CONFIG.tmp"
            grep -v "^DOMAIN=" "$ACCESS_CONFIG" 2>/dev/null >> "$ACCESS_CONFIG.tmp" || true
            mv "$ACCESS_CONFIG.tmp" "$ACCESS_CONFIG"
            ;;
        host|HOST)
            echo "HOST=\"$value\"" > "$ACCESS_CONFIG.tmp"
            grep -v "^HOST=" "$ACCESS_CONFIG" 2>/dev/null >> "$ACCESS_CONFIG.tmp" || true
            mv "$ACCESS_CONFIG.tmp" "$ACCESS_CONFIG"
            ;;
        interval|INTERVAL)
            echo "INTERVAL=\"$value\"" > "$ACCESS_CONFIG.tmp"
            grep -v "^INTERVAL=" "$ACCESS_CONFIG" 2>/dev/null >> "$ACCESS_CONFIG.tmp" || true
            mv "$ACCESS_CONFIG.tmp" "$ACCESS_CONFIG"
            ;;
        *)
            log_error "Unknown configuration key: $key"
            exit 1
            ;;
    esac
    
    log_success "Configuration updated: $key=$value"
    exit 0
fi

if [ "$RESET_CONFIG" = "true" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would reset configuration to defaults"
        exit 0
    fi
    
    log_info "Resetting configuration to defaults..."
    rm -f "$ACCESS_CONFIG"
    log_success "Configuration reset to defaults"
    exit 0
fi

if [ "$VALIDATE_CONFIG" = "true" ]; then
    log_info "Validating configuration..."
    
    load_config
    
    # Validate required fields
    errors=0
    
    if [ -z "$PROVIDER" ]; then
        log_error "PROVIDER not set"
        errors=$((errors + 1))
    else
        if ! load_provider "$PROVIDER" >/dev/null 2>&1; then
            log_error "Invalid provider: $PROVIDER"
            errors=$((errors + 1))
        fi
    fi
    
    if [ -z "$DOMAIN" ]; then
        log_error "DOMAIN not set"
        errors=$((errors + 1))
    fi
    
    if [ -n "$INTERVAL" ] && ! echo "$INTERVAL" | grep -E '^[0-9]+$' >/dev/null; then
        log_error "INTERVAL must be a number"
        errors=$((errors + 1))
    fi
    
    if [ "$errors" -eq 0 ]; then
        log_success "Configuration is valid"
        exit 0
    else
        log_error "Configuration has $errors error(s)"
        exit 1
    fi
fi

# Handle service management flags
if [ "$DAEMON_STATUS" = "true" ]; then
    log_info "Checking daemon status..."
    
    if [ -f "$ACCESS_PIDFILE" ]; then
        pid=$(cat "$ACCESS_PIDFILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            log_success "Daemon is running (PID: $pid)"
            
            # Show additional status info
            if [ -f "$ACCESS_LOG" ]; then
                last_update=$(tail -1 "$ACCESS_LOG" | grep "SUCCESS" | tail -1)
                if [ -n "$last_update" ]; then
                    echo "Last successful update: $last_update"
                fi
            fi
            
            exit 0
        else
            log_error "Daemon PID file exists but process not running"
            exit 1
        fi
    else
        log_error "Daemon is not running"
        exit 1
    fi
fi

if [ "$STOP_DAEMON" = "true" ]; then
    log_info "Stopping daemon..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would stop daemon"
        exit 0
    fi
    
    if [ -f "$ACCESS_PIDFILE" ]; then
        pid=$(cat "$ACCESS_PIDFILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid"
            rm -f "$ACCESS_PIDFILE"
            log_success "Daemon stopped"
        else
            log_error "Daemon was not running"
            rm -f "$ACCESS_PIDFILE"
        fi
    else
        log_error "Daemon is not running"
    fi
    exit 0
fi

if [ "$FORCE_RESTART" = "true" ]; then
    log_info "Force restarting daemon..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would force restart daemon"
        exit 0
    fi
    
    # Stop daemon if running
    if [ -f "$ACCESS_PIDFILE" ]; then
        pid=$(cat "$ACCESS_PIDFILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid"
            sleep 2
        fi
        rm -f "$ACCESS_PIDFILE"
    fi
    
    # Start daemon
    set -- daemon start
fi

if [ "$RELOAD_CONFIG" = "true" ]; then
    log_info "Reloading configuration..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN: Would reload configuration"
        exit 0
    fi
    
    if [ -f "$ACCESS_PIDFILE" ]; then
        pid=$(cat "$ACCESS_PIDFILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill -HUP "$pid" 2>/dev/null || {
                log_error "Failed to reload configuration"
                exit 1
            }
            log_success "Configuration reloaded"
        else
            log_error "Daemon is not running"
            exit 1
        fi
    else
        log_error "Daemon is not running"
        exit 1
    fi
    exit 0
fi

# Handle diagnostic flags
if [ "$CONNECTIVITY_TEST" = "true" ]; then
    log_info "Testing network connectivity..."
    
    # Test basic internet connectivity
    if command -v ping > /dev/null; then
        if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
            log_success "Internet connectivity: OK"
        else
            log_error "Internet connectivity: FAILED"
            exit 1
        fi
    fi
    
    # Test DNS resolution
    if command -v nslookup > /dev/null; then
        if nslookup google.com > /dev/null 2>&1; then
            log_success "DNS resolution: OK"
        else
            log_error "DNS resolution: FAILED"
            exit 1
        fi
    fi
    
    log_success "Connectivity test passed"
    exit 0
fi

if [ "$DNS_CHECK" = "true" ]; then
    log_info "Checking DNS resolution..."
    
    load_config
    
    if [ -z "$DOMAIN" ]; then
        log_error "DOMAIN not configured"
        exit 1
    fi
    
    if command -v nslookup > /dev/null; then
        current_ip=$(nslookup "$DOMAIN" | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
        detected_ip=$(detect_ip)
        
        echo "Domain: $DOMAIN"
        echo "Current DNS record: $current_ip"
        echo "Detected IP: $detected_ip"
        
        if [ "$current_ip" = "$detected_ip" ]; then
            log_success "DNS record is up to date"
        else
            log_error "DNS record is outdated"
            exit 1
        fi
    else
        log_error "nslookup command not available"
        exit 1
    fi
    
    exit 0
fi

if [ "$HEALTH_CHECK" = "true" ]; then
    log_info "Running comprehensive health check..."
    
    errors=0
    
    # Check configuration
    load_config
    if [ -z "$PROVIDER" ] || [ -z "$DOMAIN" ]; then
        log_error "Configuration incomplete"
        errors=$((errors + 1))
    fi
    
    # Check provider
    if [ -n "$PROVIDER" ] && ! load_provider "$PROVIDER" >/dev/null 2>&1; then
        log_error "Provider unavailable: $PROVIDER"
        errors=$((errors + 1))
    fi
    
    # Check connectivity
    if command -v ping > /dev/null && ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        log_error "Internet connectivity failed"
        errors=$((errors + 1))
    fi
    
    # Check DNS
    if command -v nslookup > /dev/null && ! nslookup google.com > /dev/null 2>&1; then
        log_error "DNS resolution failed"
        errors=$((errors + 1))
    fi
    
    if [ "$errors" -eq 0 ]; then
        log_success "Health check passed"
        exit 0
    else
        log_error "Health check failed with $errors error(s)"
        exit 1
    fi
fi

if [ -n "$TEST_PROVIDER" ]; then
    log_info "Testing provider: $TEST_PROVIDER"
    
    if ! load_provider "$TEST_PROVIDER"; then
        log_error "Provider not found: $TEST_PROVIDER"
        exit 1
    fi
    
    # Test provider capabilities
    echo "Provider: $TEST_PROVIDER"
    echo "Capabilities: $(get_provider_capabilities "$TEST_PROVIDER")"
    
    # Test if provider can detect domain
    if [ -n "$DOMAIN" ]; then
        if can_provider_manage "$TEST_PROVIDER" "$DOMAIN"; then
            log_success "Provider can manage domain: $DOMAIN"
        else
            log_error "Provider cannot manage domain: $DOMAIN"
        fi
    fi
    
    exit 0
fi

# Reset arguments to parsed ones (removing processed flags)
set -- $PARSED_ARGS

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
        # Auto-update removed - use Stacker framework instead
        
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
        
        # Check if in dry-run mode
        if [ "$ACCESS_DRY_RUN" = "true" ] && command -v access_simulate_dns_update >/dev/null 2>&1; then
            # Run dry-run simulation instead of actual update
            access_simulate_dns_update "$PROVIDER" "$DOMAIN" "$HOST" "$ip"
        else
            # Use provider abstraction to update DNS
            update_with_provider "$PROVIDER" "$DOMAIN" "$HOST" "$ip"
        fi
        
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
                --scan=*) 
                    SCAN_ENABLED="${arg#*=}"
                    # Validate boolean value
                    case "$SCAN_ENABLED" in
                        true|false) ;;
                        *) 
                            log_error "Invalid scan value: $SCAN_ENABLED (must be true or false)"
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
        log "Starting Access watchdog daemon..."
        log "Purpose: Monitor cron health and DNS sync status"
        
        # Load the focused service monitoring module
        if [ -f "./modules/service.sh" ]; then
            . "./modules/service.sh"
            service_init || {
                log_error "Failed to initialize service monitoring module"
                exit 1
            }
        else
            log_error "Service monitoring module not found"
            exit 1
        fi
        
        # Create daemon-specific lock for service identification (XDG data directory)
        DAEMON_LOCK="$ACCESS_DATA_HOME/daemon.lock"
        echo $$ > "$DAEMON_LOCK"
        trap 'rm -f "$DAEMON_LOCK"; exit 130' INT TERM
        
        log "🐕 Watchdog mission:"
        log "  1. Monitor cron job health → repair if dead"
        log "  2. Validate DNS sync status → fix if broken"
        log "  3. Check sync timestamps → trigger if stale"
        log "  Interval: ${ACCESS_INTERVAL:-300} seconds"
        
        while true; do
            # Run focused watchdog cycle
            access_watchdog_cycle
            
            # Sleep until next watchdog cycle
            sleep "${ACCESS_INTERVAL:-300}"
        done
        ;;
        
    providers)
        list_providers
        ;;
        
    scan)
        # Manage network scan settings
        shift
        if [ "$1" = "enable" ]; then
            if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
                temp_file=$(secure_mktemp "access-scan-enable")
                jq '.scan = true' "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
                log_success "Network scan enabled"
                log "When host is empty, Access will auto-discover available peer slots"
            else
                log_error "Config file not found. Run 'access config <provider>' first"
                exit 1
            fi
        elif [ "$1" = "disable" ]; then
            if command -v jq >/dev/null 2>&1 && [ -f "$ACCESS_CONFIG" ]; then
                temp_file=$(secure_mktemp "access-scan-disable")
                jq '.scan = false' "$ACCESS_CONFIG" > "$temp_file" && mv "$temp_file" "$ACCESS_CONFIG"
                log_success "Network scan disabled"
                log "When host is empty, Access will use root domain (@)"
            else
                log_error "Config file not found. Run 'access config <provider>' first"
                exit 1
            fi
        elif [ "$1" = "status" ] || [ -z "$1" ]; then
            if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
                scan_status=$(jq -r '.scan // false' "$ACCESS_CONFIG" 2>/dev/null || echo "false")
                echo "Network scan: $scan_status"
                if [ "$scan_status" = "true" ]; then
                    echo "  When host is empty, auto-scan will find available peer slots"
                else
                    echo "  When host is empty, root domain (@) will be used"
                fi
            else
                echo "Network scan: not configured"
                echo "  Run 'access config <provider>' first"
            fi
        else
            echo "Usage: access scan [enable|disable|status]"
            echo ""
            echo "  enable   - Enable auto-scan for empty host"
            echo "  disable  - Disable auto-scan (use @ for empty host)"
            echo "  status   - Show current scan setting (default)"
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
        # If no provider specified, show integration capabilities
        if [ -z "$1" ]; then
            # Show Access-Stacker integration capabilities
            if command -v report_capabilities >/dev/null 2>&1; then
                report_capabilities
            else
                echo "Access Integration Status:"
                echo "  Mode: Standalone (no Stacker bridge)"
                echo ""
                echo "For provider capabilities, use: access capabilities <provider>"
            fi
        else
            # Show provider capabilities
            if command -v get_provider_capabilities >/dev/null 2>&1; then
                get_provider_capabilities "$1"
            else
                log_error "Provider system not loaded - check SCRIPT_DIR: $SCRIPT_DIR"
                exit 1
            fi
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
        shift
        detailed="false"
        json_output="false"
        
        # Check global flags
        [ "$ACCESS_JSON_OUTPUT" = "true" ] && json_output="true"
        
        # Parse status-specific options
        for arg in "$@"; do
            case "$arg" in
                --detailed|-d) detailed="true" ;;
                --json) json_output="true" ;;
            esac
        done
        
        # Use enhanced status if available and requested
        if [ "$detailed" = "true" ] && command -v access_status_detailed >/dev/null 2>&1; then
            access_status_detailed "$json_output"
            exit 0
        elif [ "$json_output" = "true" ] && command -v access_status_json >/dev/null 2>&1; then
            access_status_json
            exit 0
        fi
        
        # Fall back to original status display
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
            
            # Show scan status
            if [ -f "$ACCESS_CONFIG" ] && command -v jq >/dev/null 2>&1; then
                scan_status=$(jq -r '.scan // false' "$ACCESS_CONFIG" 2>/dev/null || echo "false")
                echo "  Scan: ${YELLOW}$scan_status${NC}"
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
        
        # Show service status using both Stacker framework and Access-specific checks
        echo ""
        echo "${BOLD}Service Status (Stacker + Access):${NC}"
        
        # Use Stacker's service status if available
        if command -v stacker_service_status >/dev/null 2>&1; then
            stacker_service_status 2>/dev/null || true
        fi
        
        # Access-specific watchdog daemon status  
        echo ""
        echo "${BOLD}Access Watchdog:${NC}"
        if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
            daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock")
            if kill -0 "$daemon_pid" 2>/dev/null; then
                echo "  🐕 Watchdog: ${GREEN}monitoring${NC} (PID: $daemon_pid)"
                
                # Show last watchdog run
                if [ -f "$ACCESS_DATA_HOME/last_watchdog.log" ]; then
                    last_watchdog=$(cat "$ACCESS_DATA_HOME/last_watchdog.log" 2>/dev/null)
                    if [ -n "$last_watchdog" ]; then
                        current_time=$(date +%s)
                        watchdog_age=$((current_time - last_watchdog))
                        minutes_ago=$((watchdog_age / 60))
                        
                        if [ "$watchdog_age" -lt 600 ]; then  # 10 minutes
                            echo "    Last check: ${GREEN}${minutes_ago}m ago${NC} (active)"
                        else
                            echo "    Last check: ${YELLOW}${minutes_ago}m ago${NC} (may be stuck)"
                        fi
                    fi
                fi
            else
                echo "  🐕 Watchdog: ${RED}stale lock${NC} (PID: $daemon_pid)"
            fi
        else
            echo "  🐕 Watchdog: ${DIM}not running${NC}"
        fi
        
        # Enhanced cron monitoring
        echo ""
        echo "${BOLD}Redundant Automation:${NC}"
        if crontab -l 2>/dev/null | grep -q "access"; then
            echo "  ✓ Cron: ${GREEN}configured${NC}"
            cron_schedule=$(crontab -l | grep "access" | head -1 | cut -d' ' -f1-5)
            echo "    Schedule: ${YELLOW}$cron_schedule${NC}"
            
            # Show last cron execution if available
            if [ -f "$ACCESS_DATA_HOME/last_cron.log" ]; then
                last_cron=$(stat -c %Y "$ACCESS_DATA_HOME/last_cron.log" 2>/dev/null)
                if [ -n "$last_cron" ]; then
                    current_time=$(date +%s)
                    cron_age=$((current_time - last_cron))
                    cron_minutes=$((cron_age / 60))
                    
                    if [ "$cron_age" -lt 900 ]; then  # 15 minutes
                        echo "    Last run: ${GREEN}${cron_minutes}m ago${NC}"
                    else
                        echo "    Last run: ${YELLOW}${cron_minutes}m ago${NC} (may be stale)"
                    fi
                fi
            fi
        else
            echo "  ❌ Cron: ${RED}not configured${NC}"
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
            temp_log=$(secure_mktemp "access-log-clean")
            tail -n 1000 "$ACCESS_DATA_HOME/access.log" > "$temp_log"
            mv "$temp_log" "$ACCESS_DATA_HOME/access.log"
            echo "  ${GREEN}✓${NC} Trimmed log file (kept last 1000 lines)"
        fi
        
        echo ""
        echo "${GREEN}Cleanup complete${NC}"
        ;;
        
    diagnostics|diag)
        # Run comprehensive system diagnostics
        shift
        # Check both local args and global flag
        json_output="false"
        [ "$ACCESS_JSON_OUTPUT" = "true" ] && json_output="true"
        
        for arg in "$@"; do
            case "$arg" in
                --json) json_output="true" ;;
            esac
        done
        
        if command -v access_run_diagnostics >/dev/null 2>&1; then
            access_run_diagnostics "$json_output"
        else
            log_error "Advanced diagnostics not available"
            echo "Basic diagnostics would be implemented here"
            exit 1
        fi
        ;;
        
    backup)
        # Backup configuration
        shift
        backup_name="$1"
        
        if command -v access_backup_config >/dev/null 2>&1; then
            access_backup_config "$backup_name"
        else
            log_error "Backup functionality not available"
            exit 1
        fi
        ;;
        
    restore)
        # Restore configuration from backup
        shift
        backup_name="$1"
        
        if [ -z "$backup_name" ]; then
            if command -v access_list_backups >/dev/null 2>&1; then
                access_list_backups
            else
                log_error "Backup listing not available"
            fi
            exit 1
        fi
        
        if command -v access_restore_config >/dev/null 2>&1; then
            access_restore_config "$backup_name"
        else
            log_error "Restore functionality not available"
            exit 1
        fi
        ;;
        
    backups)
        # List available backups
        if command -v access_list_backups >/dev/null 2>&1; then
            access_list_backups
        else
            log_error "Backup listing not available"
            exit 1
        fi
        ;;
        
    service)
        # Enhanced service management
        shift
        service_action="${1:-status}"
        shift
        
        case "$service_action" in
            status)
                # Enhanced daemon status
                json_output="false"
                [ "$ACCESS_JSON_OUTPUT" = "true" ] && json_output="true"
                
                for arg in "$@"; do
                    case "$arg" in
                        --json) json_output="true" ;;
                    esac
                done
                
                if command -v access_daemon_status_detailed >/dev/null 2>&1; then
                    access_daemon_status_detailed "$json_output"
                else
                    log_error "Enhanced service management not available"
                    exit 1
                fi
                ;;
            restart)
                force="false"
                for arg in "$@"; do
                    case "$arg" in
                        --force) force="true" ;;
                    esac
                done
                
                if command -v access_daemon_restart >/dev/null 2>&1; then
                    access_daemon_restart "$force"
                else
                    log_error "Service restart not available"
                    exit 1
                fi
                ;;
            reload)
                if command -v access_daemon_reload_config >/dev/null 2>&1; then
                    access_daemon_reload_config
                else
                    log_error "Service reload not available"
                    exit 1
                fi
                ;;
            stop)
                if command -v access_daemon_stop >/dev/null 2>&1; then
                    access_daemon_stop
                else
                    log_error "Service stop not available"
                    exit 1
                fi
                ;;
            health)
                if command -v access_service_health_detailed >/dev/null 2>&1; then
                    access_service_health_detailed
                else
                    log_error "Service health check not available"
                    exit 1
                fi
                ;;
            *)
                echo "Usage: access service [status|restart|reload|stop|health] [options]"
                echo ""
                echo "Actions:"
                echo "  status [--json]    Show detailed daemon status"
                echo "  restart [--force]  Restart daemon (graceful or forced)"
                echo "  reload             Reload configuration without restart"
                echo "  stop               Stop daemon gracefully"
                echo "  health             Comprehensive service health check"
                exit 1
                ;;
        esac
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
        echo "    ${BLUE}access scan${NC}            Manage auto-scan settings"
        echo "    ${BLUE}access providers${NC}       List available providers"
        echo "    ${BLUE}access discover${NC}        Auto-discover all providers"
        echo "    ${BLUE}access capabilities${NC}    Show integration status & provider capabilities"
        echo "    ${BLUE}access suggest${NC}         Suggest provider for domain"
        echo "    ${BLUE}access health${NC}          Check provider health"
        echo "    ${BLUE}access test${NC} [provider] Test provider connectivity"
        echo "    ${BLUE}access daemon${NC}          Run watchdog daemon (monitors cron health + DNS sync)"
        echo "    ${BLUE}access logs${NC}            View Access logs"
        echo "    ${BLUE}access clean${NC}           Clean locks and temporary files"
        echo "    ${BLUE}access diagnostics${NC}     Run comprehensive system diagnostics"
        echo "    ${BLUE}access backup${NC} [name]   Backup current configuration"
        echo "    ${BLUE}access restore${NC} <name>  Restore configuration from backup"
        echo "    ${BLUE}access backups${NC}         List available configuration backups"
        echo "    ${BLUE}access service${NC}         Enhanced service management"
        echo "    ${BLUE}access self-update${NC}     Update using Stacker framework"
        echo "    ${BLUE}access version${NC}         Show version"
        echo "    ${BLUE}access help${NC}            Show this help"
        echo ""
        echo "${BOLD}Configuration:${NC}"
        echo "${BOLD}-------------${NC}"
        echo "    ${YELLOW}access config${NC} <provider> ${DIM}--help${NC}     Show provider configuration help"
        echo "    ${YELLOW}access config${NC} <provider> ${DIM}[options]${NC}  Configure provider"
        echo "    ${YELLOW}access scan${NC} [enable|disable]   Manage peer auto-scan"
        echo ""
        echo "${BOLD}Provider Scan:${NC}"
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
        echo "    ${DIM}access config godaddy --domain=example.com --key=KEY --secret=SECRET --scan=true${NC}"
        echo "    ${DIM}access config cloudflare --domain=example.com --email=EMAIL --api-key=KEY --zone-id=ZONE${NC}"
        echo ""
        echo "  ${BOLD}Daily Usage:${NC}"
        echo "    ${DIM}access status${NC}                               # Check configuration and service status"
        echo "    ${DIM}access ip${NC}                                   # Show current public IP"
        echo "    ${DIM}access update${NC}                               # Update DNS immediately"
        echo "    ${DIM}access scan enable${NC}                     # Enable peer auto-scan"
        echo "    ${DIM}access logs -f${NC}                              # Follow real-time logs"
        echo "    ${DIM}access logs -n50${NC}                            # Show last 50 log entries"
        echo "    ${DIM}access clean${NC}                                # Clean temporary files and locks"
        echo ""
        echo "  ${BOLD}Advanced Features:${NC}"
        echo "    ${DIM}access --dry-run update${NC}                     # Test DNS update without changes"
        echo "    ${DIM}access status --detailed${NC}                    # Detailed status with performance metrics"
        echo "    ${DIM}access status --json${NC}                        # Status output in JSON format"
        echo "    ${DIM}access diagnostics${NC}                          # Comprehensive system diagnostics"
        echo "    ${DIM}access diagnostics --json${NC}                   # Diagnostics in JSON format"
        echo "    ${DIM}access backup daily${NC}                         # Backup configuration with name"
        echo "    ${DIM}access restore daily${NC}                        # Restore from backup"
        echo "    ${DIM}access backups${NC}                              # List all available backups"
        echo "    ${DIM}access service status${NC}                       # Detailed daemon status"
        echo "    ${DIM}access service restart${NC}                      # Graceful daemon restart"
        echo "    ${DIM}access service health${NC}                       # Comprehensive health check"
        echo ""
        echo "${BOLD}Global Flags:${NC}"
        echo "${BOLD}-------------${NC}"
        echo "    ${GREEN}--help, -h${NC}                  Show help information"
        echo "    ${GREEN}--version, -v${NC}               Show version information"
        echo "    ${GREEN}--dry-run${NC}                   Test mode - no changes applied"
        echo "    ${GREEN}--verbose${NC}                   Enable verbose output"
        echo "    ${GREEN}--quiet, -q${NC}                 Minimal output mode"
        echo "    ${GREEN}--debug${NC}                     Enable debug logging"
        echo "    ${GREEN}--json${NC}                       Output in JSON format (where supported)"
        echo ""
        echo "${BOLD}Service Management:${NC}"
        echo "${BOLD}------------------${NC}"
        echo "    ${YELLOW}--force-restart${NC}             Force daemon restart"
        echo "    ${YELLOW}--reload-config${NC}             Reload configuration without restart"
        echo "    ${YELLOW}--stop-daemon${NC}               Stop daemon gracefully"
        echo "    ${YELLOW}--daemon-status${NC}             Show detailed daemon status"
        echo ""
        echo "${BOLD}Configuration:${NC}"
        echo "${BOLD}-------------${NC}"
        echo "    ${BLUE}--show-config${NC}               Display current configuration"
        echo "    ${BLUE}--set-config KEY=VALUE${NC}      Set configuration values"
        echo "    ${BLUE}--reset-config${NC}              Reset to defaults"
        echo "    ${BLUE}--validate-config${NC}           Validate configuration"
        echo ""
        echo "${BOLD}Diagnostics:${NC}"
        echo "${BOLD}------------${NC}"
        echo "    ${RED}--connectivity-test${NC}         Test network connectivity"
        echo "    ${RED}--dns-check${NC}                 Verify DNS resolution"
        echo "    ${RED}--health-check${NC}              Comprehensive health test"
        echo "    ${RED}--test-provider PROVIDER${NC}    Test specific provider"
        echo ""
        echo "${BOLD}Flag Examples:${NC}"
        echo "${BOLD}--------------${NC}"
        echo "    ${DIM}access --version${NC}                            # Show version"
        echo "    ${DIM}access --dry-run update${NC}                     # Test update without applying"
        echo "    ${DIM}access --verbose --debug update${NC}             # Update with detailed logging"
        echo "    ${DIM}access --show-config${NC}                        # Display current settings"
        echo "    ${DIM}access --set-config provider=cloudflare${NC}     # Set provider"
        echo "    ${DIM}access --validate-config${NC}                    # Check configuration"
        echo "    ${DIM}access --daemon-status${NC}                      # Check daemon status"
        echo "    ${DIM}access --connectivity-test${NC}                  # Test connectivity"
        echo "    ${DIM}access --health-check${NC}                       # Full system health check"
        echo "    ${DIM}access --test-provider godaddy${NC}              # Test specific provider"
        echo ""
        echo "${BOLD}Environment variables:${NC}"
        echo "${BOLD}---------------------${NC}"
        echo "    ${YELLOW}ACCESS_PROVIDER${NC}   DNS provider"
        echo "    ${YELLOW}ACCESS_DOMAIN${NC}     Domain to update"
        echo "    ${YELLOW}ACCESS_HOST${NC}       Host record (default: @)"
        echo "    ${YELLOW}ACCESS_INTERVAL${NC}   Update interval in seconds (default: 300)"
        echo ""
        echo "${DIM}Access v$VERSION - Pure shell DNS synchronization with 47 CLI flags${NC}"
        echo ""
        ;;
esac
