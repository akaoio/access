#!/bin/sh
# Access Peer Health Check - POSIX Compliant Version
# Uses inetd or simple file-based health status
# Pure POSIX shell implementation

set -e

# Configuration
HEALTH_PORT="${HEALTH_PORT:-8089}"
HEALTH_FILE="${HEALTH_FILE:-$HOME/.local/share/access/health.status}"
DISCOVERY_STATE="${DISCOVERY_STATE:-$HOME/.local/share/access/discovery.state}"
HEALTH_LOG="${HEALTH_LOG:-$HOME/.local/share/access/health.log}"

# POSIX compliant logging
log() {
    printf "[Health] %s\n" "$*"
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$HEALTH_LOG" 2>/dev/null || true
}

warn() {
    printf "[Warning] %s\n" "$*" >&2
}

error() {
    printf "[Error] %s\n" "$*" >&2
}

# Initialize health system
init_health() {
    # Ensure directories exist
    health_dir=$(dirname "$HEALTH_FILE")
    log_dir=$(dirname "$HEALTH_LOG")
    
    mkdir -p "$health_dir" "$log_dir"
}

# Get peer information (POSIX compliant)
get_peer_info() {
    if [ -f "$DISCOVERY_STATE" ]; then
        peer_host=$(sed -n 's/.*"peer_host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_STATE")
        peer_slot=$(sed -n 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$DISCOVERY_STATE")
        full_domain=$(sed -n 's/.*"full_domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_STATE")
        
        printf '{"peer":"%s","slot":%s,"domain":"%s","status":"alive","timestamp":"%s"}' \
            "$peer_host" "${peer_slot:-0}" "$full_domain" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    else
        printf '{"status":"unconfigured","timestamp":"%s"}' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    fi
}

# Update health file (POSIX compliant alternative to HTTP server)
update_health_file() {
    init_health
    
    # Write current health status to file
    health_info=$(get_peer_info)
    printf "%s\n" "$health_info" > "$HEALTH_FILE"
    
    # Make it readable by others (for monitoring)
    chmod 644 "$HEALTH_FILE"
    
    log "Updated health file: $HEALTH_FILE"
}

# Monitor health continuously (POSIX compliant daemon)
monitor_health() {
    log "Starting health monitor (file-based)..."
    
    # Update health file periodically
    while true; do
        update_health_file
        
        # Also check if we can reach other peers
        if [ -f "$DISCOVERY_STATE" ]; then
            peer_slot=$(sed -n 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$DISCOVERY_STATE")
            
            # Check next peer in sequence
            next_slot=$((peer_slot + 1))
            next_peer="peer${next_slot}.$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DISCOVERY_STATE" || echo "akao.io")"
            
            # Try to check if next peer exists (POSIX compliant)
            if nslookup "$next_peer" >/dev/null 2>&1; then
                log "Peer $next_peer exists in DNS"
            fi
        fi
        
        # Sleep for 30 seconds
        sleep 30
    done
}

# Setup inetd service (POSIX compliant TCP server)
setup_inetd() {
    log "Setting up inetd health service..."
    
    # Create response script
    response_script="/usr/local/bin/access-health-respond"
    
    {
        printf '#!/bin/sh\n'
        printf '# Auto-generated Access health responder\n'
        printf 'read -r request\n'
        printf 'health_file="%s"\n' "$HEALTH_FILE"
        printf 'if [ -f "$health_file" ]; then\n'
        printf '    content=$(cat "$health_file")\n'
        printf '    length=${#content}\n'
        printf '    printf "HTTP/1.1 200 OK\\r\\n"\n'
        printf '    printf "Content-Type: application/json\\r\\n"\n'
        printf '    printf "Content-Length: %%d\\r\\n" "$length"\n'
        printf '    printf "Connection: close\\r\\n"\n'
        printf '    printf "\\r\\n"\n'
        printf '    printf "%%s" "$content"\n'
        printf 'else\n'
        printf '    printf "HTTP/1.1 503 Service Unavailable\\r\\n"\n'
        printf '    printf "Content-Length: 0\\r\\n"\n'
        printf '    printf "\\r\\n"\n'
        printf 'fi\n'
    } > "$response_script"
    
    chmod +x "$response_script"
    
    # Add to inetd.conf (requires root)
    inetd_line="$HEALTH_PORT stream tcp nowait nobody $response_script"
    
    printf "\n"
    printf "To enable health endpoint on port %s, add this line to /etc/inetd.conf:\n" "$HEALTH_PORT"
    printf "  %s\n" "$inetd_line"
    printf "\n"
    printf "Then restart inetd:\n"
    printf "  sudo pkill -HUP inetd\n"
    printf "\n"
    
    # Alternative: xinetd configuration
    xinetd_config="/etc/xinetd.d/access-health"
    
    printf "Or create %s:\n" "$xinetd_config"
    printf "service access-health\n"
    printf "{\n"
    printf "    type = UNLISTED\n"
    printf "    port = %s\n" "$HEALTH_PORT"
    printf "    socket_type = stream\n"
    printf "    protocol = tcp\n"
    printf "    wait = no\n"
    printf "    user = nobody\n"
    printf "    server = %s\n" "$response_script"
    printf "    disable = no\n"
    printf "}\n"
}

# Simple file-based health check (most POSIX compliant)
check_peer_health() {
    peer="$1"
    
    # Method 1: Check if peer's health file is accessible via SSH
    if command -v ssh >/dev/null 2>&1; then
        if ssh -o ConnectTimeout=2 -o BatchMode=yes "$peer" "cat $HEALTH_FILE" 2>/dev/null | grep -q "alive"; then
            printf "Peer %s is healthy\n" "$peer"
            return 0
        fi
    fi
    
    # Method 2: Check DNS and assume healthy if exists
    if nslookup "$peer" >/dev/null 2>&1; then
        printf "Peer %s exists in DNS (assumed healthy)\n" "$peer"
        return 0
    fi
    
    printf "Peer %s is not responding\n" "$peer"
    return 1
}

# Test health system
test_health() {
    log "Testing health system..."
    
    # Update health file
    update_health_file
    
    # Show contents
    printf "Health status:\n"
    if [ -f "$HEALTH_FILE" ]; then
        cat "$HEALTH_FILE"
        printf "\n"
    else
        error "Health file not created"
    fi
    
    # Try to check other peers
    printf "\nChecking other peers:\n"
    check_peer_health "peer0.akao.io"
    check_peer_health "peer1.akao.io"
}

# Main command handler (POSIX compliant)
case "${1:-start}" in
    start)
        init_health
        monitor_health
        ;;
    update)
        update_health_file
        ;;
    test)
        test_health
        ;;
    setup-inetd)
        setup_inetd
        ;;
    check)
        if [ -z "$2" ]; then
            error "Usage: $0 check <peer-hostname>"
            exit 1
        fi
        check_peer_health "$2"
        ;;
    status)
        if [ -f "$HEALTH_FILE" ]; then
            printf "Health file: %s\n" "$HEALTH_FILE"
            cat "$HEALTH_FILE"
            printf "\n"
            printf "Last modified: "
            ls -l "$HEALTH_FILE" | awk '{print $6, $7, $8}'
        else
            warn "No health file found"
            exit 1
        fi
        ;;
    *)
        printf "Access Health Check (POSIX Compliant)\n"
        printf "\n"
        printf "Usage: %s {start|update|test|setup-inetd|check|status}\n" "$0"
        printf "\n"
        printf "Commands:\n"
        printf "  start       - Start health monitoring (continuous)\n"
        printf "  update      - Update health file once\n"
        printf "  test        - Test health system\n"
        printf "  setup-inetd - Show inetd configuration for TCP server\n"
        printf "  check <peer>- Check if peer is healthy\n"
        printf "  status      - Show current health status\n"
        printf "\n"
        printf "This POSIX-compliant version uses file-based health status\n"
        printf "instead of HTTP servers, making it work on any POSIX system.\n"
        printf "\n"
        printf "Health file location: %s\n" "$HEALTH_FILE"
        exit 1
        ;;
esac