#!/bin/sh
# Daemon script for Access Eternal - Real-time IP monitoring
set -e

# Get paths from init.sh if available
if [ -f "$(dirname "$0")/init.sh" ]; then
    . "$(dirname "$0")/init.sh"
elif [ -f "/usr/local/lib/access/init.sh" ]; then
    . "/usr/local/lib/access/init.sh"
else
    # Fallback defaults
    BIN="/usr/local/bin/access"
    LIB="/usr/local/lib/access"
    STATE="/var/lib/access"
fi

# Ensure we have access command
if [ ! -f "$BIN" ]; then
    printf "ERROR: Access binary not found at %s\n" "$BIN" >&2
    exit 1
fi

# Create log directory
LOG_DIR="/var/log/access"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log_info() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_DIR/access.log"
}

log_error() {
    printf "[%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_DIR/error.log"
    printf "[%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
}

# Signal handlers for graceful shutdown
cleanup() {
    log_info "Daemon shutting down gracefully"
    exit 0
}

trap cleanup TERM INT

log_info "Starting Access daemon - real-time IP monitoring"

# Main monitoring loop
while true; do
    log_info "Starting IP monitor session"
    
    # Monitor IP address changes using ip monitor
    if ip monitor addr 2>/dev/null | while read -r line; do
        case "$line" in
            *"scope global"*)
                log_info "IP change detected: $line"
                if "$BIN" sync 2>>"$LOG_DIR/error.log"; then
                    log_info "DNS sync successful"
                else
                    log_error "DNS sync failed, will retry on next change"
                fi
                ;;
        esac
    done; then
        log_info "IP monitor exited normally"
    else
        log_error "IP monitor failed, restarting in 5 seconds"
    fi
    
    sleep 5
done