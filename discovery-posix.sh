#!/bin/sh
# Access Network Discovery Module - POSIX Compliant Version
# Pure POSIX shell implementation for swarm coordination
# No bash-specific features, no external dependencies beyond POSIX.1

set -e

# Configuration
DISCOVERY_CONFIG="${DISCOVERY_CONFIG:-$HOME/.config/access/discovery.json}"
DISCOVERY_LOG="${DISCOVERY_LOG:-$HOME/.config/access/discovery.log}"
DISCOVERY_STATE="${DISCOVERY_STATE:-$HOME/.local/share/access/discovery.state}"

# Default values
DEFAULT_DOMAIN="akao.io"
DEFAULT_HOST_PREFIX="peer"
DEFAULT_CHECK_INTERVAL=300  # 5 minutes
DEFAULT_HEAL_INTERVAL=60    # 1 minute when healing

# POSIX compliant output (no colors in strict POSIX mode)
log() {
    printf "[Discovery] %s\n" "$*"
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$DISCOVERY_LOG" 2>/dev/null || true
}

warn() {
    printf "[Warning] %s\n" "$*" >&2
    printf "[%s] WARNING: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$DISCOVERY_LOG" 2>/dev/null || true
}

error() {
    printf "[Error] %s\n" "$*" >&2
    printf "[%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$DISCOVERY_LOG" 2>/dev/null || true
}

info() {
    printf "[Info] %s\n" "$*"
}

# Create necessary directories (POSIX compliant)
init_discovery() {
    # Use POSIX dirname
    config_dir=$(dirname "$DISCOVERY_CONFIG")
    state_dir=$(dirname "$DISCOVERY_STATE")
    log_dir=$(dirname "$DISCOVERY_LOG")
    
    mkdir -p "$config_dir" "$state_dir" "$log_dir"
}

# Load discovery configuration (POSIX compliant JSON parsing)
load_discovery_config() {
    if [ -f "$DISCOVERY_CONFIG" ]; then
        # POSIX compliant JSON extraction using sed
        DOMAIN=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_CONFIG" 2>/dev/null)
        HOST_PREFIX=$(sed -n 's/.*"host_prefix"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_CONFIG" 2>/dev/null)
        DNS_KEY=$(sed -n 's/.*"dns_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_CONFIG" 2>/dev/null)
        DNS_SECRET=$(sed -n 's/.*"dns_secret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_CONFIG" 2>/dev/null)
        DNS_PROVIDER=$(sed -n 's/.*"dns_provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_CONFIG" 2>/dev/null)
        ENABLE_AUTO_SYNC=$(sed -n 's/.*"enable_auto_sync"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$DISCOVERY_CONFIG" 2>/dev/null)
        
        # Set defaults if empty
        DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
        HOST_PREFIX="${HOST_PREFIX:-$DEFAULT_HOST_PREFIX}"
        ENABLE_AUTO_SYNC="${ENABLE_AUTO_SYNC:-false}"
    else
        # Use defaults
        DOMAIN="$DEFAULT_DOMAIN"
        HOST_PREFIX="$DEFAULT_HOST_PREFIX"
        DNS_KEY=""
        DNS_SECRET=""
        DNS_PROVIDER=""
        ENABLE_AUTO_SYNC="false"
    fi
}

# Save discovery configuration (POSIX compliant)
save_discovery_config() {
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
    } > "$DISCOVERY_CONFIG"
    
    chmod 600 "$DISCOVERY_CONFIG"
}

# POSIX compliant peer checking (no bash TCP, no nc dependency)
check_peer_alive() {
    peer_host="$1"
    full_domain="${peer_host}.${DOMAIN}"
    
    # Method 1: Check DNS record exists (POSIX compliant)
    if command -v nslookup >/dev/null 2>&1; then
        # nslookup is in POSIX.1-2001
        if nslookup "$full_domain" 8.8.8.8 2>/dev/null | grep -q "Address:.*[0-9]"; then
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
                if curl -s -f --connect-timeout 2 "http://${full_domain}:80/" >/dev/null 2>&1; then
                    return 0  # HTTP responding
                fi
            fi
            
            # DNS exists but not reachable - consider it occupied
            warn "Peer $full_domain has DNS but is not reachable"
            return 0  # Still occupied
        else
            # No DNS record - slot is available
            return 1
        fi
    elif command -v host >/dev/null 2>&1; then
        # Try host command as fallback (common but not POSIX)
        if host "$full_domain" 8.8.8.8 2>/dev/null | grep -q "has address"; then
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

# Find the lowest available peer slot (POSIX compliant)
find_lowest_available_slot() {
    slot=0
    max_slots=1000
    
    info "Scanning for available peer slots..."
    
    while [ "$slot" -lt "$max_slots" ]; do
        peer_host="${HOST_PREFIX}${slot}"
        
        if ! check_peer_alive "$peer_host"; then
            log "Found available slot: ${peer_host}.${DOMAIN}"
            printf "%d" "$slot"
            return 0
        else
            info "Slot $slot is occupied (${peer_host}.${DOMAIN})"
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
    
    # Update DNS based on provider
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
            error "DNS provider '$DNS_PROVIDER' not supported for auto-discovery"
            return 1
            ;;
    esac
    
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
    } > "$DISCOVERY_STATE"
    
    log "Successfully registered as $full_domain"
    return 0
}

# Update GoDaddy DNS (POSIX compliant using wget/curl)
update_godaddy_dns() {
    host="$1"
    ip="$2"
    
    api_url="https://api.godaddy.com/v1/domains/${DOMAIN}/records/A/${host}"
    
    # Prefer curl, fallback to wget
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -s -X PUT "$api_url" \
            -H "Authorization: sso-key ${DNS_KEY}:${DNS_SECRET}" \
            -H "Content-Type: application/json" \
            -d "[{\"data\":\"${ip}\",\"ttl\":600}]" 2>&1)
    elif command -v wget >/dev/null 2>&1; then
        response=$(wget -q -O - --method=PUT \
            --header="Authorization: sso-key ${DNS_KEY}:${DNS_SECRET}" \
            --header="Content-Type: application/json" \
            --body-data="[{\"data\":\"${ip}\",\"ttl\":600}]" \
            "$api_url" 2>&1)
    else
        error "Neither curl nor wget available for API calls"
        return 1
    fi
    
    # Check for error in response
    if printf "%s" "$response" | grep -q "error"; then
        error "GoDaddy update failed: $response"
        return 1
    fi
    
    return 0
}

# Monitor and heal the swarm (POSIX compliant)
monitor_and_heal() {
    log "Starting swarm monitoring and self-healing..."
    
    # Load our current state
    if [ -f "$DISCOVERY_STATE" ]; then
        current_slot=$(sed -n 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$DISCOVERY_STATE" 2>/dev/null)
        
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
            temp_file="${DISCOVERY_STATE}.tmp"
            sed "s/\"last_heartbeat\":.*/\"last_heartbeat\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"/" "$DISCOVERY_STATE" > "$temp_file"
            mv "$temp_file" "$DISCOVERY_STATE"
        fi
    else
        warn "No current registration found. Running initial discovery..."
        run_discovery
    fi
}

# Interactive setup mode (POSIX compliant input)
interactive_setup() {
    printf "\n"
    printf "ACCESS NETWORK DISCOVERY SETUP\n"
    printf "==================================\n"
    printf "\n"
    printf "This will configure automatic peer discovery and self-healing\n"
    printf "for the Access distributed network.\n"
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
    printf "Auto-sync network discovery will:\n"
    printf "  • Scan %s0.%s, %s1.%s, etc.\n" "$HOST_PREFIX" "$DOMAIN" "$HOST_PREFIX" "$DOMAIN"
    printf "  • Find the lowest available slot\n"
    printf "  • Automatically register this peer\n"
    printf "  • Self-heal by migrating to lower slots when available\n"
    printf "\n"
    printf "Enable auto-sync network discovery? [Y/n]: "
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
        save_discovery_config
        
        # Run discovery
        printf "\n"
        log "Starting network discovery..."
        slot=$(find_lowest_available_slot)
        
        if [ -n "$slot" ]; then
            full_domain="${HOST_PREFIX}${slot}.${DOMAIN}"
            printf "\n"
            printf "======================================\n"
            printf "  DISCOVERY RESULT\n"
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
        save_discovery_config
        log "Auto-sync disabled. You can enable it later."
    fi
    
    printf "\n"
    log "Discovery setup complete!"
}

# Non-interactive setup mode (POSIX compliant)
non_interactive_setup() {
    # Use environment variables or defaults
    DOMAIN="${ACCESS_DISCOVERY_DOMAIN:-$DEFAULT_DOMAIN}"
    HOST_PREFIX="${ACCESS_DISCOVERY_PREFIX:-$DEFAULT_HOST_PREFIX}"
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
    save_discovery_config
    
    log "Running automatic discovery..."
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

# Run discovery process (POSIX compliant)
run_discovery() {
    init_discovery
    load_discovery_config
    
    if [ "$ENABLE_AUTO_SYNC" = "true" ]; then
        slot=$(find_lowest_available_slot)
        
        if [ -n "$slot" ]; then
            register_peer "$slot"
        else
            error "No available peer slots"
            return 1
        fi
    else
        warn "Auto-sync is disabled. Run 'access discovery setup' to enable."
        return 1
    fi
}

# Daemon mode for continuous monitoring (POSIX compliant)
run_daemon() {
    log "Starting discovery daemon..."
    
    while true; do
        monitor_and_heal
        
        # Sleep interval (shorter if actively healing)
        if [ -f "$DISCOVERY_STATE" ]; then
            current_slot=$(sed -n 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$DISCOVERY_STATE" 2>/dev/null)
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
case "${1:-}" in
    setup)
        if [ -t 0 ]; then
            interactive_setup
        else
            non_interactive_setup
        fi
        ;;
    discover)
        run_discovery
        ;;
    monitor)
        monitor_and_heal
        ;;
    daemon)
        run_daemon
        ;;
    status)
        if [ -f "$DISCOVERY_STATE" ]; then
            cat "$DISCOVERY_STATE"
        else
            warn "No discovery state found. Run '$0 setup' first."
        fi
        ;;
    *)
        printf "Access Network Discovery Module (POSIX Compliant)\n"
        printf "\n"
        printf "Usage: %s {setup|discover|monitor|daemon|status}\n" "$0"
        printf "\n"
        printf "Commands:\n"
        printf "  setup    - Interactive setup wizard\n"
        printf "  discover - Find and claim lowest available peer slot\n"
        printf "  monitor  - Check swarm health and self-heal if needed\n"
        printf "  daemon   - Run continuous monitoring and self-healing\n"
        printf "  status   - Show current peer registration status\n"
        printf "\n"
        printf "Environment variables for non-interactive mode:\n"
        printf "  ACCESS_DISCOVERY_DOMAIN   - Main domain (default: akao.io)\n"
        printf "  ACCESS_DISCOVERY_PREFIX   - Host prefix (default: peer)\n"
        printf "  ACCESS_DNS_PROVIDER      - DNS provider (godaddy|cloudflare|digitalocean)\n"
        printf "  ACCESS_DNS_KEY           - API key for DNS provider\n"
        printf "  ACCESS_DNS_SECRET        - API secret (if required)\n"
        printf "\n"
        exit 1
        ;;
esac