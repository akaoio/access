#!/bin/sh
# Access Peer Health Check Server
# Simple HTTP server that responds to health checks for peer discovery
# Pure POSIX shell implementation using netcat

set -e

# Configuration
HEALTH_PORT="${HEALTH_PORT:-8089}"
HEALTH_LOG="${HEALTH_LOG:-$HOME/.local/share/access/health.log}"
DISCOVERY_STATE="${DISCOVERY_STATE:-$HOME/.local/share/access/discovery.state}"

# Colors for output
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    GREEN=''
    YELLOW=''
    NC=''
fi

log() {
    echo "${GREEN}[Health]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$HEALTH_LOG"
}

warn() {
    echo "${YELLOW}[Warning]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" >> "$HEALTH_LOG"
}

# Get peer information
get_peer_info() {
    if [ -f "$DISCOVERY_STATE" ]; then
        local peer_host=$(grep '"peer_host"' "$DISCOVERY_STATE" | sed 's/.*"peer_host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        local peer_slot=$(grep '"peer_slot"' "$DISCOVERY_STATE" | sed 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
        local full_domain=$(grep '"full_domain"' "$DISCOVERY_STATE" | sed 's/.*"full_domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        echo "{\"peer\":\"$peer_host\",\"slot\":$peer_slot,\"domain\":\"$full_domain\",\"status\":\"alive\"}"
    else
        echo "{\"status\":\"unconfigured\"}"
    fi
}

# Start simple HTTP server using netcat
start_health_server() {
    log "Starting health check server on port $HEALTH_PORT..."
    
    # Create response
    create_response() {
        local peer_info=$(get_peer_info)
        local content_length=${#peer_info}
        
        echo "HTTP/1.1 200 OK"
        echo "Content-Type: application/json"
        echo "Content-Length: $content_length"
        echo "Access-Control-Allow-Origin: *"
        echo "Connection: close"
        echo ""
        echo "$peer_info"
    }
    
    # Check if nc supports -l -p syntax or just -l
    if nc -h 2>&1 | grep -q "\-p port"; then
        # Traditional netcat syntax
        NC_CMD="nc -l -p $HEALTH_PORT"
    else
        # OpenBSD netcat syntax
        NC_CMD="nc -l $HEALTH_PORT"
    fi
    
    # Main server loop
    while true; do
        # Handle one request
        (
            # Read request (we don't really parse it, just respond to any GET)
            while IFS= read -r line; do
                # Empty line marks end of headers
                [ -z "$line" ] || [ "$line" = $'\r' ] && break
            done
            
            # Send response
            create_response
        ) | $NC_CMD
        
        # Log the request
        log "Served health check request"
        
        # Small delay to prevent rapid cycling
        sleep 0.1
    done
}

# Alternative using Python if available (more reliable)
start_python_server() {
    log "Starting health check server using Python on port $HEALTH_PORT..."
    
    python3 -c "
import json
import http.server
import socketserver
import os

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            state_file = '$DISCOVERY_STATE'
            response = {'status': 'unconfigured'}
            
            if os.path.exists(state_file):
                try:
                    with open(state_file, 'r') as f:
                        state = json.load(f)
                        response = {
                            'peer': state.get('peer_host', 'unknown'),
                            'slot': state.get('peer_slot', -1),
                            'domain': state.get('full_domain', 'unknown'),
                            'status': 'alive'
                        }
                except:
                    pass
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_error(404)
    
    def log_message(self, format, *args):
        return  # Suppress default logging

with socketserver.TCPServer(('', $HEALTH_PORT), HealthHandler) as httpd:
    print('Health server running on port $HEALTH_PORT')
    httpd.serve_forever()
" 2>/dev/null
}

# Alternative using simple bash tcp server
start_bash_server() {
    log "Starting health check server using bash on port $HEALTH_PORT..."
    
    while true; do
        # Use bash's /dev/tcp if available
        exec 3<>/dev/tcp/localhost/$HEALTH_PORT 2>/dev/null || {
            warn "Cannot bind to port $HEALTH_PORT"
            sleep 5
            continue
        }
        
        # Read request
        while IFS= read -r line <&3; do
            [ -z "$line" ] || [ "$line" = $'\r' ] && break
        done
        
        # Send response
        peer_info=$(get_peer_info)
        content_length=${#peer_info}
        
        echo -e "HTTP/1.1 200 OK\r" >&3
        echo -e "Content-Type: application/json\r" >&3
        echo -e "Content-Length: $content_length\r" >&3
        echo -e "Connection: close\r" >&3
        echo -e "\r" >&3
        echo -n "$peer_info" >&3
        
        exec 3<&-
        exec 3>&-
        
        log "Served health check request"
    done
}

# Check dependencies and start appropriate server
start_server() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$HEALTH_LOG")"
    
    # Try Python first (most reliable)
    if command -v python3 >/dev/null 2>&1; then
        start_python_server
    # Try netcat
    elif command -v nc >/dev/null 2>&1; then
        start_health_server
    # Try bash tcp
    elif [ -n "$BASH_VERSION" ]; then
        start_bash_server
    else
        warn "No suitable method found to start health server"
        warn "Install python3 or netcat for better reliability"
        exit 1
    fi
}

# Daemon mode
run_daemon() {
    log "Starting health check daemon..."
    
    # Ensure we're not already running
    if [ -f "/tmp/access-health.pid" ]; then
        old_pid=$(cat /tmp/access-health.pid)
        if kill -0 "$old_pid" 2>/dev/null; then
            warn "Health server already running (PID: $old_pid)"
            exit 1
        fi
    fi
    
    # Save PID
    echo $$ > /tmp/access-health.pid
    
    # Trap signals for cleanup
    trap 'rm -f /tmp/access-health.pid; exit' INT TERM EXIT
    
    # Start server
    start_server
}

# Main command handler
case "${1:-start}" in
    start)
        start_server
        ;;
    daemon)
        run_daemon
        ;;
    status)
        if [ -f "/tmp/access-health.pid" ]; then
            pid=$(cat /tmp/access-health.pid)
            if kill -0 "$pid" 2>/dev/null; then
                log "Health server is running (PID: $pid)"
                exit 0
            else
                warn "Health server PID file exists but process is not running"
                exit 1
            fi
        else
            warn "Health server is not running"
            exit 1
        fi
        ;;
    test)
        log "Testing health endpoint..."
        peer_info=$(get_peer_info)
        echo "Response: $peer_info"
        ;;
    *)
        echo "Usage: $0 {start|daemon|status|test}"
        echo ""
        echo "Commands:"
        echo "  start  - Start health check server (foreground)"
        echo "  daemon - Start as background daemon"
        echo "  status - Check if server is running"
        echo "  test   - Test health response locally"
        echo ""
        echo "The health server listens on port $HEALTH_PORT and responds to /health"
        exit 1
        ;;
esac