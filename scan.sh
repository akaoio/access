#!/bin/sh
# Access Network Scan Module - POSIX Compliant Version
# Pure POSIX shell implementation for swarm coordination
# No bash-specific features, no external dependencies beyond POSIX.1

set -e

# Source required modules for integration
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/providers.sh" ]; then
    . "$SCRIPT_DIR/providers.sh"
fi

# Load validation functions needed by providers
# Fallback implementations if access.sh not available
validate_domain_name() {
    local domain="$1"
    [ -z "$domain" ] && return 1
    [ ${#domain} -gt 253 ] && return 1
    [ ${#domain} -lt 1 ] && return 1
    case "$domain" in
        *[^a-zA-Z0-9.-]*) return 1 ;;
        .*|*.|*-|-*|*..*|*-.*|*.-*) return 1 ;;
    esac
    return 0
}

validate_hostname() {
    local hostname="$1"
    [ -z "$hostname" ] && return 1
    [ "$hostname" = "@" ] && return 0
    [ ${#hostname} -gt 63 ] && return 1
    case "$hostname" in
        *[^a-zA-Z0-9-]*) return 1 ;;
        -*|*-) return 1 ;;
    esac
    return 0
}

validate_ip_address() {
    local ip="$1"
    [ -z "$ip" ] && return 1
    if echo "$ip" | grep -q '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$'; then
        local IFS='.'
        set -- $ip
        [ $# -eq 4 ] || return 1
        for octet in "$@"; do
            case "$octet" in
                ''|*[!0-9]*) return 1 ;;
            esac
            [ "$octet" -gt 255 ] && return 1
        done
        return 0
    fi
    # Basic IPv6 check
    echo "$ip" | grep -q ':' && return 0
    return 1
}

# Configuration
SCAN_CONFIG="${SCAN_CONFIG:-$HOME/.config/access/scan.json}"
SCAN_LOG="${SCAN_LOG:-$HOME/.config/access/scan.log}"
SCAN_STATE="${SCAN_STATE:-$HOME/.local/share/access/scan.state}"

# Default values
DEFAULT_DOMAIN=""  # Use domain from Access config, not hardcoded
DEFAULT_HOST_PREFIX="peer"
DEFAULT_CHECK_INTERVAL=300  # 5 minutes
DEFAULT_HEAL_INTERVAL=60    # 1 minute when healing

# POSIX compliant output (no colors in strict POSIX mode)
log() {
    printf "[Scan] %s\n" "$*" >&2
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$SCAN_LOG" 2>/dev/null || true
}

warn() {
    printf "[Warning] %s\n" "$*" >&2
    printf "[%s] WARNING: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$SCAN_LOG" 2>/dev/null || true
}

error() {
    printf "[Error] %s\n" "$*" >&2
    printf "[%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$SCAN_LOG" 2>/dev/null || true
}

info() {
    printf "[Info] %s\n" "$*" >&2
}

# Create necessary directories (POSIX compliant)
init_scan() {
    # Use POSIX dirname
    config_dir=$(dirname "$SCAN_CONFIG")
    state_dir=$(dirname "$SCAN_STATE")
    log_dir=$(dirname "$SCAN_LOG")
    
    mkdir -p "$config_dir" "$state_dir" "$log_dir"
}

# Load scan configuration (POSIX compliant JSON parsing)
load_scan_config() {
    # First try to load from Access main config if domain not set
    ACCESS_CONFIG="${ACCESS_CONFIG:-$HOME/.config/access/config.json}"
    if [ -z "$DOMAIN" ] && [ -f "$ACCESS_CONFIG" ]; then
        # Try to get domain from Access config
        if command -v jq >/dev/null 2>&1; then
            DOMAIN=$(jq -r '.domain // ""' "$ACCESS_CONFIG" 2>/dev/null)
        else
            DOMAIN=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ACCESS_CONFIG" 2>/dev/null)
        fi
    fi
    
    if [ -f "$SCAN_CONFIG" ]; then
        # POSIX compliant JSON extraction using sed
        DOMAIN="${DOMAIN:-$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)}"
        HOST_PREFIX=$(sed -n 's/.*"host_prefix"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
        DNS_KEY=$(sed -n 's/.*"dns_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
        DNS_SECRET=$(sed -n 's/.*"dns_secret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
        DNS_PROVIDER=$(sed -n 's/.*"dns_provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
        ENABLE_AUTO_SYNC=$(sed -n 's/.*"enable_auto_sync"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$SCAN_CONFIG" 2>/dev/null)
        
        # Set defaults if empty
        DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
        HOST_PREFIX="${HOST_PREFIX:-$DEFAULT_HOST_PREFIX}"
        ENABLE_AUTO_SYNC="${ENABLE_AUTO_SYNC:-false}"
    else
        # Use defaults
        DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
        HOST_PREFIX="${HOST_PREFIX:-$DEFAULT_HOST_PREFIX}"
        DNS_KEY=""
        DNS_SECRET=""
        DNS_PROVIDER=""
        ENABLE_AUTO_SYNC="false"
    fi
}

# Save scan configuration (POSIX compliant)
save_scan_config() {
    # Create config with printf (POSIX)
    {
        printf '{\n'
        printf '    "domain": "%s",\n' "$DOMAIN"
        printf '    "host_prefix": "%s",\n' "$HOST_PREFIX"
        printf '    "dns_provider": "%s",\n' "$DNS_PROVIDER"
        printf '    "dns_key": "%s",\n' "$DNS_KEY"
        printf '    "dns_secret": "%s",\n' "$DNS_SECRET"
        printf '    "enable_auto_sync": %s,\n' "$ENABLE_AUTO_SYNC"
        printf '    "last_updated": "%s"\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf '}\n'
    } > "$SCAN_CONFIG"
    
    chmod 600 "$SCAN_CONFIG"
}

# POSIX compliant peer checking (no bash TCP, no nc dependency)
check_peer_alive() {
    peer_host="$1"
    full_domain="${peer_host}.${DOMAIN}"
    
    # Get our current IPs (both IPv4 and IPv6)
    my_ipv4=$(get_public_ip 2>/dev/null || true)
    my_ipv6=""
    if command -v curl >/dev/null 2>&1; then
        my_ipv6=$(curl -6 -s ipv6.icanhazip.com 2>/dev/null || true)
    fi
    
    # Method 1: Check DNS record exists (POSIX compliant)
    if command -v nslookup >/dev/null 2>&1; then
        # nslookup is in POSIX.1-2001
        local dns_server="${ACCESS_DNS_SERVER:-8.8.8.8}"
        peer_ip=$(nslookup "$full_domain" "$dns_server" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        
        if [ -n "$peer_ip" ]; then
            # Check if this peer is us (our IPv4 or IPv6)
            if [ "$peer_ip" = "$my_ipv4" ] || [ "$peer_ip" = "$my_ipv6" ]; then
                log "Slot ${peer_host} is ours (IP: $peer_ip)"
                return 0  # Our own slot, occupied
            fi
            
            # DNS exists, now check if reachable
            
            # Method 2: Try telnet to SSH port (POSIX.1)
            if command -v telnet >/dev/null 2>&1; then
                # Send a newline and check for SSH banner
                if printf "\n" | telnet "$full_domain" 22 2>/dev/null | grep -q "SSH"; then
                    return 0  # Peer is alive - SSH responding
                fi
            fi
            
            # Method 3: Try wget with timeout (POSIX, but wget not guaranteed)
            if command -v wget >/dev/null 2>&1; then
                if wget -q -O /dev/null -T 2 "http://${full_domain}:80/" 2>/dev/null; then
                    return 0  # HTTP responding
                fi
            fi
            
            # Method 4: Try curl if available (not POSIX but common)
            if command -v curl >/dev/null 2>&1; then
                local timeout="${ACCESS_TIMEOUT:-2}"
                if curl -s -f --connect-timeout "$timeout" "http://${full_domain}:80/" >/dev/null 2>&1; then
                    return 0  # HTTP responding
                fi
            fi
            
            # DNS exists but not reachable - slot can be reclaimed
            info "Peer $full_domain has stale DNS - slot available for reclaim"
            return 1  # Available for reclaim
        else
            # No DNS record - slot is available
            return 1
        fi
    elif command -v host >/dev/null 2>&1; then
        # Try host command as fallback (common but not POSIX)
        local dns_server="${ACCESS_DNS_SERVER:-8.8.8.8}"
        if host "$full_domain" "$dns_server" 2>/dev/null | grep -q "has address"; then
            return 0  # DNS exists, assume occupied
        else
            return 1  # No DNS, available
        fi
    else
        # No DNS tools available - fallback to ping (POSIX.1)
        if ping -c 1 -W 2 "$full_domain" >/dev/null 2>&1; then
            return 0  # Responds to ping
        else
            return 1  # No response, assume available
        fi
    fi
}

# Find our existing peer slot if we already have one
find_existing_peer_slot() {
    # Get our current IPs
    my_ipv4=$(get_public_ip 2>/dev/null || true)
    my_ipv6=""
    if command -v curl >/dev/null 2>&1; then
        my_ipv6=$(curl -6 -s ipv6.icanhazip.com 2>/dev/null || true)
    fi
    
    # Check if we already have a peer slot
    slot=0
    max_slots="${ACCESS_MAX_SLOTS:-100}"
    
    log "Checking if we already have a peer slot..." >&2
    
    while [ "$slot" -lt "$max_slots" ]; do
        peer_host="${HOST_PREFIX}${slot}"
        full_domain="${peer_host}.${DOMAIN}"
        
        if command -v nslookup >/dev/null 2>&1; then
            local dns_server="${ACCESS_DNS_SERVER:-8.8.8.8}"
        peer_ip=$(nslookup "$full_domain" "$dns_server" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
            
            if [ "$peer_ip" = "$my_ipv4" ] || [ "$peer_ip" = "$my_ipv6" ]; then
                log "Found our existing slot: ${peer_host} (IP: $peer_ip)" >&2
                printf "%d" "$slot"
                return 0
            fi
        fi
        
        slot=$((slot + 1))
    done
    
    return 1  # No existing slot found
}

# Find the lowest available peer slot (POSIX compliant)
find_lowest_available_slot() {
    # First check if we already have a slot
    existing_slot=$(find_existing_peer_slot)
    if [ $? -eq 0 ] && [ -n "$existing_slot" ]; then
        log "Using our existing slot: ${HOST_PREFIX}${existing_slot}" >&2
        printf "%d" "$existing_slot"
        return 0
    fi
    
    slot=0
    max_slots="${ACCESS_MAX_SLOTS:-100}"  # Reduced from 1000 to avoid excessive scanning
    
    # Quiet mode - only log important info
    log "Scanning for available peer slots (0-$max_slots)..."
    
    while [ "$slot" -lt "$max_slots" ]; do
        peer_host="${HOST_PREFIX}${slot}"
        
        if ! check_peer_alive "$peer_host"; then
            log "Found available slot: ${peer_host}.${DOMAIN}"
            printf "%d" "$slot"
            return 0
        fi
        
        # Only log every 10th slot to reduce noise
        if [ $((slot % 10)) -eq 0 ] && [ "$slot" -gt 0 ]; then
            log "Scanned up to slot $slot..."
        fi
        
        slot=$((slot + 1))
    done
    
    error "No available slots found in first $max_slots positions"
    return 1
}

# Get current public IP (POSIX compliant)
get_public_ip() {
    # Try multiple methods to get IP
    ip=""
    
    # Method 1: curl (common, not POSIX)
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -s checkip.amazonaws.com 2>/dev/null || true)
        [ -n "$ip" ] && printf "%s" "$ip" && return 0
        
        ip=$(curl -s ipv4.icanhazip.com 2>/dev/null || true)
        [ -n "$ip" ] && printf "%s" "$ip" && return 0
    fi
    
    # Method 2: wget (POSIX but not guaranteed)
    if command -v wget >/dev/null 2>&1; then
        ip=$(wget -q -O - checkip.amazonaws.com 2>/dev/null || true)
        [ -n "$ip" ] && printf "%s" "$ip" && return 0
        
        ip=$(wget -q -O - ipv4.icanhazip.com 2>/dev/null || true)
        [ -n "$ip" ] && printf "%s" "$ip" && return 0
    fi
    
    # Method 3: Use access if available
    if [ -x "/usr/local/bin/access" ]; then
        ip=$(/usr/local/bin/access ip 2>/dev/null || true)
        [ -n "$ip" ] && printf "%s" "$ip" && return 0
    fi
    
    error "Cannot detect public IP address"
    return 1
}

# Register this peer with DNS provider (POSIX compliant)
register_peer() {
    peer_slot="$1"
    peer_host="${HOST_PREFIX}${peer_slot}"
    full_domain="${peer_host}.${DOMAIN}"
    
    log "Registering as $full_domain..."
    
    # Get current public IP
    public_ip=$(get_public_ip)
    
    if [ -z "$public_ip" ]; then
        error "Cannot detect public IP address"
        return 1
    fi
    
    info "Public IP: $public_ip"
    
    # Update DNS using provider abstraction layer
    if [ -n "$DNS_PROVIDER" ]; then
        log "Using provider abstraction layer for $DNS_PROVIDER"
        
        # Validate inputs before calling provider
        if ! validate_domain_name "$DOMAIN"; then
            error "Invalid domain name: $DOMAIN"
            return 1
        fi
        
        if ! validate_hostname "$peer_host"; then
            error "Invalid hostname: $peer_host"
            return 1
        fi
        
        if ! validate_ip_address "$public_ip"; then
            error "Invalid IP address: $public_ip"
            return 1
        fi
        
        # Set provider credentials from scan configuration
        case "$DNS_PROVIDER" in
            godaddy)
                GODADDY_KEY="$DNS_KEY"
                GODADDY_SECRET="$DNS_SECRET"
                GODADDY_DOMAIN="$DOMAIN"
                export GODADDY_KEY GODADDY_SECRET GODADDY_DOMAIN
                ;;
            cloudflare)
                CLOUDFLARE_EMAIL="$CLOUDFLARE_EMAIL"
                CLOUDFLARE_API_KEY="$DNS_KEY"
                CLOUDFLARE_ZONE_ID="$CLOUDFLARE_ZONE_ID"
                CLOUDFLARE_DOMAIN="$DOMAIN"
                export CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY CLOUDFLARE_ZONE_ID CLOUDFLARE_DOMAIN
                ;;
            digitalocean)
                DIGITALOCEAN_TOKEN="$DNS_KEY"
                DIGITALOCEAN_DOMAIN="$DOMAIN"
                export DIGITALOCEAN_TOKEN DIGITALOCEAN_DOMAIN
                ;;
        esac
        
        # Use provider abstraction layer if available
        if command -v update_with_provider >/dev/null 2>&1; then
            if update_with_provider "$DNS_PROVIDER" "$DOMAIN" "$peer_host" "$public_ip"; then
                log "DNS update successful via provider abstraction layer"
            else
                error "DNS update failed via provider abstraction layer"
                return 1
            fi
        else
            # Fallback to direct provider methods (backward compatibility)
            log "Provider abstraction layer not available, using direct methods"
            case "$DNS_PROVIDER" in
                godaddy)
                    update_godaddy_dns "$peer_host" "$public_ip"
                    ;;
                cloudflare)
                    update_cloudflare_dns "$peer_host" "$public_ip"
                    ;;
                digitalocean)
                    update_digitalocean_dns "$peer_host" "$public_ip"
                    ;;
                *)
                    error "DNS provider '$DNS_PROVIDER' not supported for auto-scan"
                    return 1
                    ;;
            esac
        fi
    else
        error "No DNS provider configured for auto-scan"
        return 1
    fi
    
    # Save our peer state (POSIX compliant)
    {
        printf '{\n'
        printf '    "peer_slot": %d,\n' "$peer_slot"
        printf '    "peer_host": "%s",\n' "$peer_host"
        printf '    "full_domain": "%s",\n' "$full_domain"
        printf '    "public_ip": "%s",\n' "$public_ip"
        printf '    "registered_at": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf '    "last_heartbeat": "%s"\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf '}\n'
    } > "$SCAN_STATE"
    
    log "Successfully registered as $full_domain"
    return 0
}

# Removed hardcoded update_godaddy_dns - now using provider abstraction layer

# Monitor and heal the swarm (POSIX compliant)
monitor_and_heal() {
    log "Starting swarm monitoring and self-healing..."
    
    # Load our current state
    if [ -f "$SCAN_STATE" ]; then
        current_slot=$(sed -n 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$SCAN_STATE" 2>/dev/null)
        
        if [ -n "$current_slot" ]; then
            info "Currently registered as peer${current_slot}"
            
            # Check if a lower slot is available
            slot=0
            while [ "$slot" -lt "$current_slot" ]; do
                peer_host="${HOST_PREFIX}${slot}"
                
                if ! check_peer_alive "$peer_host"; then
                    warn "Lower slot $slot is now available! Migrating..."
                    
                    # Register in new slot
                    if register_peer "$slot"; then
                        log "Successfully migrated to peer${slot}"
                        return 0
                    else
                        error "Failed to migrate to peer${slot}"
                    fi
                fi
                
                slot=$((slot + 1))
            done
            
            # Update heartbeat (POSIX compliant sed)
            temp_file="${SCAN_STATE}.tmp"
            sed "s/\"last_heartbeat\":.*/\"last_heartbeat\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"/" "$SCAN_STATE" > "$temp_file"
            mv "$temp_file" "$SCAN_STATE"
        fi
    else
        warn "No current registration found. Running initial scan..."
        run_scan
    fi
}

# Interactive setup mode (POSIX compliant input)
interactive_setup() {
    printf "\n"
    printf "ACCESS NETWORK SCAN SETUP (OPTIONAL FEATURE)\n"
    printf "===============================================\n"
    printf "\n"
    printf "⚠️  IMPORTANT: This is an OPTIONAL advanced feature\n"
    printf "\n"
    printf "The scan/peer discovery feature enables:\n"
    printf "  • Automatic coordination between multiple Access instances\n"
    printf "  • Load balancing across multiple IP addresses\n"
    printf "  • Self-healing peer network management\n"
    printf "\n"
    printf "❓ Do you need this feature?\n"
    printf "  ✓ YES: If you have multiple systems running Access\n"
    printf "  ✓ YES: If you want automatic load distribution\n"
    printf "  ✗ NO:  If you have a single system (most common)\n"
    printf "  ✗ NO:  If you only need basic dynamic DNS\n"
    printf "\n"
    printf "Continue with scan setup? (y/N): "
    read -r continue_setup
    
    case "$continue_setup" in
        [yY]|[yY][eE][sS])
            printf "✓ Continuing with scan setup...\n"
            ;;
        *)
            printf "Setup cancelled. Access will work perfectly without scan.\n"
            printf "You can enable this later with: access scan setup\n"
            exit 0
            ;;
    esac
    printf "\n"
    
    # Domain configuration
    printf "Main domain [%s]: " "$DEFAULT_DOMAIN"
    read -r input_domain
    DOMAIN="${input_domain:-$DEFAULT_DOMAIN}"
    
    # Host prefix configuration
    printf "Host prefix [%s]: " "$DEFAULT_HOST_PREFIX"
    read -r input_prefix
    HOST_PREFIX="${input_prefix:-$DEFAULT_HOST_PREFIX}"
    
    # Auto-sync configuration
    printf "\n"
    printf "Auto-sync network scan will:\n"
    printf "  • Scan %s0.%s, %s1.%s, etc.\n" "$HOST_PREFIX" "$DOMAIN" "$HOST_PREFIX" "$DOMAIN"
    printf "  • Find the lowest available slot\n"
    printf "  • Automatically register this peer\n"
    printf "  • Self-heal by migrating to lower slots when available\n"
    printf "\n"
    printf "Enable auto-sync network scan? [Y/n]: "
    read -r enable_sync
    
    if [ "$enable_sync" != "n" ] && [ "$enable_sync" != "N" ]; then
        ENABLE_AUTO_SYNC="true"
        
        # DNS provider selection
        printf "\n"
        printf "Select DNS provider for auto-registration:\n"
        printf "  1) GoDaddy\n"
        printf "  2) Cloudflare\n"
        printf "  3) DigitalOcean\n"
        printf "Choice [1-3]: "
        read -r provider_choice
        
        case "$provider_choice" in
            1)
                DNS_PROVIDER="godaddy"
                printf "GoDaddy API Key: "
                read -r DNS_KEY
                printf "GoDaddy API Secret: "
                read -r DNS_SECRET
                ;;
            2)
                DNS_PROVIDER="cloudflare"
                printf "Cloudflare Email: "
                read -r CLOUDFLARE_EMAIL
                printf "Cloudflare API Key: "
                read -r DNS_KEY
                printf "Cloudflare Zone ID: "
                read -r CLOUDFLARE_ZONE_ID
                ;;
            3)
                DNS_PROVIDER="digitalocean"
                printf "DigitalOcean API Token: "
                read -r DNS_KEY
                DNS_SECRET=""
                ;;
            *)
                error "Invalid choice"
                return 1
                ;;
        esac
        
        # Save configuration
        save_scan_config
        
        # Run scan
        printf "\n"
        log "Starting network scan..."
        slot=$(find_lowest_available_slot)
        
        if [ -n "$slot" ]; then
            full_domain="${HOST_PREFIX}${slot}.${DOMAIN}"
            printf "\n"
            printf "======================================\n"
            printf "  SCAN RESULT\n"
            printf "======================================\n"
            printf "  Available slot: %d\n" "$slot"
            printf "  Full domain: %s\n" "$full_domain"
            printf "======================================\n"
            printf "\n"
            printf "Register as %s? [Y/n]: " "$full_domain"
            read -r confirm_register
            
            if [ "$confirm_register" != "n" ] && [ "$confirm_register" != "N" ]; then
                if register_peer "$slot"; then
                    printf "\n"
                    log "Successfully joined the swarm as %s" "$full_domain"
                    log "Self-healing enabled - will migrate to lower slots when available"
                else
                    error "Failed to register peer"
                    return 1
                fi
            else
                log "Registration cancelled"
            fi
        else
            error "No available peer slots found"
            return 1
        fi
    else
        ENABLE_AUTO_SYNC="false"
        save_scan_config
        log "Auto-sync disabled. You can enable it later."
    fi
    
    printf "\n"
    log "Scan setup complete!"
}

# Non-interactive setup mode (POSIX compliant)
non_interactive_setup() {
    # Use environment variables or defaults
    DOMAIN="${ACCESS_SCAN_DOMAIN:-$DEFAULT_DOMAIN}"
    HOST_PREFIX="${ACCESS_SCAN_PREFIX:-$DEFAULT_HOST_PREFIX}"
    DNS_PROVIDER="${ACCESS_DNS_PROVIDER:-}"
    DNS_KEY="${ACCESS_DNS_KEY:-}"
    DNS_SECRET="${ACCESS_DNS_SECRET:-}"
    CLOUDFLARE_EMAIL="${ACCESS_CLOUDFLARE_EMAIL:-}"
    CLOUDFLARE_ZONE_ID="${ACCESS_CLOUDFLARE_ZONE_ID:-}"
    
    if [ -z "$DNS_PROVIDER" ] || [ -z "$DNS_KEY" ]; then
        error "Non-interactive mode requires ACCESS_DNS_PROVIDER and ACCESS_DNS_KEY"
        return 1
    fi
    
    ENABLE_AUTO_SYNC="true"
    save_scan_config
    
    log "Running automatic scan..."
    log "Domain: $DOMAIN"
    log "Host prefix: $HOST_PREFIX"
    log "Provider: $DNS_PROVIDER"
    
    # Find and register
    slot=$(find_lowest_available_slot)
    
    if [ -n "$slot" ]; then
        if register_peer "$slot"; then
            log "Automatically registered as ${HOST_PREFIX}${slot}.${DOMAIN}"
            return 0
        else
            error "Failed to register peer"
            return 1
        fi
    else
        error "No available peer slots found"
        return 1
    fi
}

# Run scan process (POSIX compliant)
run_scan() {
    init_scan
    load_scan_config
    
    if [ "$ENABLE_AUTO_SYNC" = "true" ]; then
        slot=$(find_lowest_available_slot)
        
        if [ -n "$slot" ]; then
            register_peer "$slot"
        else
            error "No available peer slots"
            return 1
        fi
    else
        warn "Auto-sync is disabled. Run 'access scan setup' to enable."
        return 1
    fi
}

# Daemon mode for continuous monitoring (POSIX compliant)
run_daemon() {
    log "Starting scan daemon..."
    
    while true; do
        monitor_and_heal
        
        # Sleep interval (shorter if actively healing)
        if [ -f "$SCAN_STATE" ]; then
            current_slot=$(sed -n 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$SCAN_STATE" 2>/dev/null)
            if [ "$current_slot" -gt 0 ]; then
                # Not in slot 0, check more frequently
                sleep "$DEFAULT_HEAL_INTERVAL"
            else
                # In optimal position, check less frequently
                sleep "$DEFAULT_CHECK_INTERVAL"
            fi
        else
            sleep "$DEFAULT_CHECK_INTERVAL"
        fi
    done
}

# Main command handler (POSIX compliant)
# Only run main logic if executed directly (not sourced)
if [ "${0##*/}" = "scan.sh" ] || [ "${0##*/}" = "access-scan" ]; then
    case "${1:-}" in
    setup)
        if [ -t 0 ]; then
            interactive_setup
        else
            non_interactive_setup
        fi
        ;;
    discover)
        run_scan
        ;;
    monitor)
        monitor_and_heal
        ;;
    daemon)
        run_daemon
        ;;
    status)
        if [ -f "$SCAN_STATE" ]; then
            cat "$SCAN_STATE"
        else
            warn "No scan state found. Run '$0 setup' first."
        fi
        ;;
    *)
        printf "Access Network Scan Module - OPTIONAL FEATURE (POSIX Compliant)\n"
        printf "\n"
        printf "⚠️  IMPORTANT: This is an OPTIONAL advanced feature for multi-system deployments\n"
        printf "   Access works perfectly for basic dynamic DNS without this feature\n"
        printf "\n"
        printf "Usage: %s {setup|discover|monitor|daemon|status}\n" "$0"
        printf "\n"
        printf "Commands:\n"
        printf "  setup    - Interactive setup wizard (explains when to use)\n"
        printf "  discover - Find and claim lowest available peer slot\n"
        printf "  monitor  - Check swarm health and self-heal if needed\n"
        printf "  daemon   - Run continuous monitoring and self-healing\n"
        printf "  status   - Show current peer registration status\n"
        printf "\n"
        printf "When to use scan/peer discovery:\n"
        printf "  ✓ Multiple systems running Access that need coordination\n"
        printf "  ✓ Load balancing across multiple IP addresses\n"
        printf "  ✓ Advanced network topologies with peer management\n"
        printf "\n"
        printf "When NOT to use scan/peer discovery:\n"
        printf "  ✗ Single system setup (most common case)\n"
        printf "  ✗ Basic home dynamic DNS needs\n"
        printf "  ✗ Simple network configurations\n"
        printf "\n"
        printf "Environment variables for non-interactive mode:\n"
        printf "  ACCESS_SCAN_DOMAIN   - Main domain (from Access config)\n"
        printf "  ACCESS_SCAN_PREFIX   - Host prefix (default: peer)\n"
        printf "  ACCESS_DNS_PROVIDER      - DNS provider (godaddy|cloudflare|digitalocean)\n"
        printf "  ACCESS_DNS_KEY           - API key for DNS provider\n"
        printf "  ACCESS_DNS_SECRET        - API secret (if required)\n"
        printf "\n"
        printf "Alternative: Use ./access-wizard scan for user-friendly configuration\n"
        printf "\n"
        exit 1
        ;;
    esac
fi