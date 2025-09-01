#!/bin/sh
# Access - Pure shell network access layer 
# Main executable for DNS synchronization

set -e

# Detect script location
SCRIPT_PATH="$0"
if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || readlink "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# Load access-init for stacker integration
if [ -f "$SCRIPT_DIR/access-init.sh" ]; then
    . "$SCRIPT_DIR/access-init.sh"
fi

# Load logging functions
if [ -f "$SCRIPT_DIR/lib/access-logging.sh" ]; then
    . "$SCRIPT_DIR/lib/access-logging.sh"
fi

# Main command handling
case "${1:-help}" in
    daemon)
        echo "Starting Access monitoring daemon..."
        echo "Monitoring DNS sync and system health..."
        
        # Set up proper daemon environment
        if command -v stacker_log >/dev/null 2>&1; then
            stacker_log "Access daemon starting with Stacker integration"
            
            # Set up Stacker service context
            export STACKER_TECH_NAME="${STACKER_TECH_NAME:-access}"
            export STACKER_SERVICE_DESCRIPTION="${STACKER_SERVICE_DESCRIPTION:-Access DNS synchronization service}"
            export STACKER_SERVICE_TYPE="${STACKER_SERVICE_TYPE:-simple}"
            
            # Create XDG directories if not exists
            if command -v stacker_create_xdg_dirs >/dev/null 2>&1; then
                stacker_create_xdg_dirs
            fi
            
            # Set up logging directory
            ACCESS_LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/access"
            mkdir -p "$ACCESS_LOG_DIR"
            ACCESS_LOG_FILE="$ACCESS_LOG_DIR/daemon.log"
        else
            ACCESS_LOG_DIR="$HOME/.local/share/access"
            mkdir -p "$ACCESS_LOG_DIR"
            ACCESS_LOG_FILE="$ACCESS_LOG_DIR/daemon.log"
        fi
        
        # Log daemon startup
        echo "[$(date)] Access daemon started (PID: $$)" >> "$ACCESS_LOG_FILE"
        
        # Main daemon loop with proper logging and error handling
        while true; do
            {
                echo "[$(date)] Starting health check cycle"
                
                # Run health check
                if [ -x "$SCRIPT_DIR/health.sh" ]; then
                    "$SCRIPT_DIR/health.sh" 2>&1 | while read -r line; do
                        echo "[$(date)] HEALTH: $line"
                    done
                else
                    echo "[$(date)] WARNING: health.sh not executable"
                fi
                
                # Run scan if configured
                if [ -x "$SCRIPT_DIR/scan.sh" ]; then
                    "$SCRIPT_DIR/scan.sh" 2>&1 | while read -r line; do
                        echo "[$(date)] SCAN: $line"
                    done
                else
                    echo "[$(date)] INFO: scan.sh not available"
                fi
                
                echo "[$(date)] Health check cycle completed"
                
            } >> "$ACCESS_LOG_FILE" 2>&1
            
            # Sleep for 5 minutes (configurable via environment)
            sleep "${ACCESS_DAEMON_INTERVAL:-300}"
        done
        ;;
    
    init)
        echo "Initializing Access..."
        if [ -x "$SCRIPT_DIR/access-wizard" ]; then
            "$SCRIPT_DIR/access-wizard"
        fi
        ;;
    
    status)
        if [ -x "$SCRIPT_DIR/health.sh" ]; then
            "$SCRIPT_DIR/health.sh" status
        fi
        ;;
    
    health)
        if [ -x "$SCRIPT_DIR/health.sh" ]; then
            "$SCRIPT_DIR/health.sh"
        fi
        ;;
    
    scan) 
        if [ -x "$SCRIPT_DIR/scan.sh" ]; then
            "$SCRIPT_DIR/scan.sh" "$@"
        fi
        ;;
    
    service)
        # Service management integration with Stacker
        if command -v stacker_require >/dev/null 2>&1; then
            export STACKER_TECH_NAME="access"
            export STACKER_SERVICE_DESCRIPTION="Access DNS synchronization service"
            export STACKER_INSTALL_DIR="${STACKER_INSTALL_DIR:-/home/x/.local/bin}"
            export STACKER_CLEAN_CLONE_DIR="$SCRIPT_DIR"
            
            # Load service module
            if stacker_require "service" 2>/dev/null; then
                case "${2:-help}" in
                    install)
                        stacker_setup_systemd_service
                        ;;
                    start)
                        stacker_start_service
                        ;;
                    stop)
                        stacker_stop_service
                        ;;
                    restart)
                        stacker_restart_service
                        ;;
                    status)
                        stacker_service_status
                        ;;
                    enable)
                        stacker_enable_service
                        ;;
                    disable)
                        stacker_disable_service
                        ;;
                    *)
                        echo "Access Service Management"
                        echo "Commands: install start stop restart status enable disable"
                        ;;
                esac
            else
                echo "ERROR: Stacker service module not available" >&2
                exit 1
            fi
        else
            echo "ERROR: Stacker framework required for service management" >&2
            exit 1
        fi
        ;;
    
    help|--help|-h)
        cat << EOF
Access - Pure Shell Network Access Layer v0.0.3

Usage: access <command> [options]

Commands:
  daemon        Run monitoring daemon
  init          Initialize with setup wizard  
  status        Show system status
  health        Run health checks
  scan          Run network scan
  service       Service management (install/start/stop/restart/status)
  help          Show this help

Service Commands:
  access service install   Install systemd service
  access service start     Start Access service
  access service stop      Stop Access service
  access service restart   Restart Access service  
  access service status    Show service status

For detailed provider management, use:
  ./providers.sh <command>

EOF
        ;;
    
    *)
        echo "Unknown command: $1"
        echo "Use 'access help' for usage information"
        exit 1
        ;;
esac