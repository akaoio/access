#!/bin/sh
# Access Network Discovery Module - Peer auto-discovery and self-healing
# Pure POSIX shell implementation for swarm coordination

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

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

log() {
    echo "${GREEN}[Discovery]${NC} $*"
}

warn() {
    echo "${YELLOW}[Warning]${NC} $*"
}

error() {
    echo "${RED}[Error]${NC} $*" >&2
}

info() {
    echo "${BLUE}[Info]${NC} $*"
}

# Create necessary directories
init_discovery() {
    mkdir -p "$(dirname "$DISCOVERY_CONFIG")"
    mkdir -p "$(dirname "$DISCOVERY_STATE")"
    mkdir -p "$(dirname "$DISCOVERY_LOG")"
}

# Load discovery configuration
load_discovery_config() {
    if [ -f "$DISCOVERY_CONFIG" ]; then
        # Parse JSON config (pure shell)
        DOMAIN=$(grep '"domain"' "$DISCOVERY_CONFIG" 2>/dev/null | sed 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "$DEFAULT_DOMAIN")
        HOST_PREFIX=$(grep '"host_prefix"' "$DISCOVERY_CONFIG" 2>/dev/null | sed 's/.*"host_prefix"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "$DEFAULT_HOST_PREFIX")
        DNS_KEY=$(grep '"dns_key"' "$DISCOVERY_CONFIG" 2>/dev/null | sed 's/.*"dns_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")
        DNS_SECRET=$(grep '"dns_secret"' "$DISCOVERY_CONFIG" 2>/dev/null | sed 's/.*"dns_secret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")
        DNS_PROVIDER=$(grep '"dns_provider"' "$DISCOVERY_CONFIG" 2>/dev/null | sed 's/.*"dns_provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")
        ENABLE_AUTO_SYNC=$(grep '"enable_auto_sync"' "$DISCOVERY_CONFIG" 2>/dev/null | sed 's/.*"enable_auto_sync"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/' || echo "false")
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

# Save discovery configuration
save_discovery_config() {
    cat > "$DISCOVERY_CONFIG" <<EOF
{
    "domain": "$DOMAIN",
    "host_prefix": "$HOST_PREFIX",
    "dns_provider": "$DNS_PROVIDER",
    "dns_key": "$DNS_KEY",
    "dns_secret": "$DNS_SECRET",
    "enable_auto_sync": $ENABLE_AUTO_SYNC,
    "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    chmod 600 "$DISCOVERY_CONFIG"
}

# Check if a peer is alive using DNS and HTTP
check_peer_alive() {
    local peer_host="$1"
    local full_domain="$peer_host.$DOMAIN"
    
    # First check if DNS record exists
    if command -v dig >/dev/null 2>&1; then
        local ip=$(dig +short "$full_domain" @8.8.8.8 2>/dev/null | head -1)
        if [ -z "$ip" ]; then
            return 1  # No DNS record
        fi
    elif command -v nslookup >/dev/null 2>&1; then
        local ip=$(nslookup "$full_domain" 8.8.8.8 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        if [ -z "$ip" ]; then
            return 1  # No DNS record
        fi
    else
        warn "No DNS tools available (dig/nslookup). Cannot verify peer."
        return 2  # Cannot check
    fi
    
    # Optional: Check if peer responds to HTTP health check
    # This assumes peers run a health endpoint (future feature)
    # For now, DNS existence is enough
    
    return 0  # Peer is alive
}

# Find the lowest available peer slot
find_lowest_available_slot() {
    local slot=0
    local max_slots=1000  # Reasonable limit
    
    info "Scanning for available peer slots..."
    
    while [ $slot -lt $max_slots ]; do
        local peer_host="${HOST_PREFIX}${slot}"
        
        if ! check_peer_alive "$peer_host"; then
            log "Found available slot: $peer_host.$DOMAIN"
            echo "$slot"
            return 0
        else
            info "Slot $slot is occupied (${peer_host}.$DOMAIN)"
        fi
        
        slot=$((slot + 1))
    done
    
    error "No available slots found in first $max_slots positions"
    return 1
}

# Register this peer with DNS provider
register_peer() {
    local peer_slot="$1"
    local peer_host="${HOST_PREFIX}${peer_slot}"
    local full_domain="$peer_host.$DOMAIN"
    
    log "Registering as $full_domain..."
    
    # Get current public IP
    local public_ip=$(./access.sh ip 2>/dev/null || curl -s checkip.amazonaws.com || curl -s ipv4.icanhazip.com)
    
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
    
    # Save our peer state
    cat > "$DISCOVERY_STATE" <<EOF
{
    "peer_slot": $peer_slot,
    "peer_host": "$peer_host",
    "full_domain": "$full_domain",
    "public_ip": "$public_ip",
    "registered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "last_heartbeat": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    log "✓ Successfully registered as $full_domain"
    return 0
}

# Update GoDaddy DNS
update_godaddy_dns() {
    local host="$1"
    local ip="$2"
    
    local api_url="https://api.godaddy.com/v1/domains/$DOMAIN/records/A/$host"
    
    local response=$(curl -s -X PUT "$api_url" \
        -H "Authorization: sso-key ${DNS_KEY}:${DNS_SECRET}" \
        -H "Content-Type: application/json" \
        -d "[{\"data\":\"$ip\",\"ttl\":600}]" 2>&1)
    
    if echo "$response" | grep -q "error"; then
        error "GoDaddy update failed: $response"
        return 1
    fi
    
    return 0
}

# Update Cloudflare DNS
update_cloudflare_dns() {
    local host="$1"
    local ip="$2"
    
    # First, get zone ID if not provided
    if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
        warn "Cloudflare zone ID not configured"
        return 1
    fi
    
    # Check if record exists
    local record_name="$host.$DOMAIN"
    local record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$record_name&type=A" \
        -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
        -H "X-Auth-Key: $DNS_KEY" | \
        grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -n "$record_id" ]; then
        # Update existing record
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "X-Auth-Key: $DNS_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":120}"
    else
        # Create new record
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "X-Auth-Key: $DNS_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":120}"
    fi
    
    return 0
}

# Update DigitalOcean DNS
update_digitalocean_dns() {
    local host="$1"
    local ip="$2"
    
    local record_name="$host"
    
    # Get existing record ID if it exists
    local record_id=$(curl -s -X GET "https://api.digitalocean.com/v2/domains/$DOMAIN/records" \
        -H "Authorization: Bearer $DNS_KEY" | \
        grep -B2 "\"name\":\"$record_name\"" | grep '"id":' | head -1 | sed 's/.*"id":\([0-9]*\).*/\1/')
    
    if [ -n "$record_id" ]; then
        # Update existing record
        curl -s -X PUT "https://api.digitalocean.com/v2/domains/$DOMAIN/records/$record_id" \
            -H "Authorization: Bearer $DNS_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"data\":\"$ip\"}"
    else
        # Create new record
        curl -s -X POST "https://api.digitalocean.com/v2/domains/$DOMAIN/records" \
            -H "Authorization: Bearer $DNS_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"$record_name\",\"data\":\"$ip\",\"ttl\":600}"
    fi
    
    return 0
}

# Monitor and heal the swarm
monitor_and_heal() {
    log "Starting swarm monitoring and self-healing..."
    
    # Load our current state
    if [ -f "$DISCOVERY_STATE" ]; then
        local current_slot=$(grep '"peer_slot"' "$DISCOVERY_STATE" | sed 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
        
        if [ -n "$current_slot" ]; then
            info "Currently registered as peer$current_slot"
            
            # Check if a lower slot is available
            local slot=0
            while [ $slot -lt $current_slot ]; do
                local peer_host="${HOST_PREFIX}${slot}"
                
                if ! check_peer_alive "$peer_host"; then
                    warn "Lower slot $slot is now available! Migrating..."
                    
                    # Deregister current slot (optional - let it expire)
                    # ...
                    
                    # Register in new slot
                    if register_peer "$slot"; then
                        log "✓ Successfully migrated to peer$slot"
                        return 0
                    else
                        error "Failed to migrate to peer$slot"
                    fi
                fi
                
                slot=$((slot + 1))
            done
            
            # Update heartbeat
            sed -i "s/\"last_heartbeat\":.*/\"last_heartbeat\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",/" "$DISCOVERY_STATE" 2>/dev/null || true
        fi
    else
        warn "No current registration found. Running initial discovery..."
        run_discovery
    fi
}

# Interactive setup mode
interactive_setup() {
    echo ""
    echo "🌐 ACCESS NETWORK DISCOVERY SETUP"
    echo "=================================="
    echo ""
    echo "This will configure automatic peer discovery and self-healing"
    echo "for the Access distributed network."
    echo ""
    
    # Domain configuration
    printf "Main domain [${DEFAULT_DOMAIN}]: "
    read -r input_domain
    DOMAIN="${input_domain:-$DEFAULT_DOMAIN}"
    
    # Host prefix configuration
    printf "Host prefix [${DEFAULT_HOST_PREFIX}]: "
    read -r input_prefix
    HOST_PREFIX="${input_prefix:-$DEFAULT_HOST_PREFIX}"
    
    # Auto-sync configuration
    echo ""
    echo "Auto-sync network discovery will:"
    echo "  • Scan ${HOST_PREFIX}0.${DOMAIN}, ${HOST_PREFIX}1.${DOMAIN}, etc."
    echo "  • Find the lowest available slot"
    echo "  • Automatically register this peer"
    echo "  • Self-heal by migrating to lower slots when available"
    echo ""
    printf "Enable auto-sync network discovery? [Y/n]: "
    read -r enable_sync
    
    if [ "$enable_sync" != "n" ] && [ "$enable_sync" != "N" ]; then
        ENABLE_AUTO_SYNC="true"
        
        # DNS provider selection
        echo ""
        echo "Select DNS provider for auto-registration:"
        echo "  1) GoDaddy"
        echo "  2) Cloudflare"
        echo "  3) DigitalOcean"
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
        echo ""
        log "Starting network discovery..."
        local slot=$(find_lowest_available_slot)
        
        if [ -n "$slot" ]; then
            local full_domain="${HOST_PREFIX}${slot}.${DOMAIN}"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  DISCOVERY RESULT"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Available slot: $slot"
            echo "  Full domain: ${GREEN}$full_domain${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            printf "Register as $full_domain? [Y/n]: "
            read -r confirm_register
            
            if [ "$confirm_register" != "n" ] && [ "$confirm_register" != "N" ]; then
                if register_peer "$slot"; then
                    echo ""
                    log "✓ Successfully joined the swarm as $full_domain"
                    log "✓ Self-healing enabled - will migrate to lower slots when available"
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
    
    echo ""
    log "Discovery setup complete!"
}

# Non-interactive setup mode
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
    local slot=$(find_lowest_available_slot)
    
    if [ -n "$slot" ]; then
        if register_peer "$slot"; then
            log "✓ Automatically registered as ${HOST_PREFIX}${slot}.${DOMAIN}"
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

# Run discovery process
run_discovery() {
    init_discovery
    load_discovery_config
    
    if [ "$ENABLE_AUTO_SYNC" = "true" ]; then
        local slot=$(find_lowest_available_slot)
        
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

# Daemon mode for continuous monitoring
run_daemon() {
    log "Starting discovery daemon..."
    
    while true; do
        monitor_and_heal
        
        # Sleep interval (shorter if actively healing)
        if [ -f "$DISCOVERY_STATE" ]; then
            local current_slot=$(grep '"peer_slot"' "$DISCOVERY_STATE" | sed 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
            if [ "$current_slot" -gt 0 ]; then
                # We're not in slot 0, check more frequently for healing opportunities
                sleep $DEFAULT_HEAL_INTERVAL
            else
                # We're in optimal position, check less frequently
                sleep $DEFAULT_CHECK_INTERVAL
            fi
        else
            sleep $DEFAULT_CHECK_INTERVAL
        fi
    done
}

# Main command handler
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
            warn "No discovery state found. Run 'access discovery setup' first."
        fi
        ;;
    *)
        echo "Access Network Discovery Module"
        echo ""
        echo "Usage: $0 {setup|discover|monitor|daemon|status}"
        echo ""
        echo "Commands:"
        echo "  setup    - Interactive setup wizard"
        echo "  discover - Find and claim lowest available peer slot"
        echo "  monitor  - Check swarm health and self-heal if needed"
        echo "  daemon   - Run continuous monitoring and self-healing"
        echo "  status   - Show current peer registration status"
        echo ""
        echo "Environment variables for non-interactive mode:"
        echo "  ACCESS_DISCOVERY_DOMAIN   - Main domain (default: akao.io)"
        echo "  ACCESS_DISCOVERY_PREFIX   - Host prefix (default: peer)"
        echo "  ACCESS_DNS_PROVIDER      - DNS provider (godaddy|cloudflare|digitalocean)"
        echo "  ACCESS_DNS_KEY           - API key for DNS provider"
        echo "  ACCESS_DNS_SECRET        - API secret (if required)"
        echo ""
        ;;
esac