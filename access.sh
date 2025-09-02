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
        echo "ERROR: Access no longer runs its own daemon"
        echo "Use 'stacker watchdog access' instead for periodic monitoring"
        echo "Or use cron for scheduled updates"
        exit 1
        ;;
    
    init)
        echo "Initializing Access..."
        if [ -x "$SCRIPT_DIR/access-wizard" ]; then
            "$SCRIPT_DIR/access-wizard"
        fi
        ;;
    
    update)
        echo "Updating DNS with current IP..."
        if [ -x "$SCRIPT_DIR/providers.sh" ]; then
            "$SCRIPT_DIR/providers.sh" update
        else
            echo "ERROR: providers.sh not found"
            exit 1
        fi
        ;;
        
    status)
        echo "Access DNS Synchronization Status"
        echo ""
        echo "  Status: ✅ Running" 
        echo "  Config: /home/x/.config/access/config.json"
        echo "  Logs: /home/x/.local/share/access/access.log"
        echo "  Home: $SCRIPT_DIR"
        echo ""
        echo "Health Status:"
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
        echo "ERROR: Scan functionality removed to reduce complexity"
        echo "Use access for basic DNS sync only"
        echo "For peer discovery, use dedicated network tools"
        exit 1
        ;;
    
    service)
        echo "ERROR: Use 'stacker service access' for service management"
        exit 1
        ;;
    
    help|--help|-h)
        cat << EOF
Access - Pure Shell Network Access Layer v0.0.1

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