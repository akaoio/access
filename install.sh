#!/bin/sh
# Access installation using Manager framework
# This replaces the complex install.sh with standardized Manager patterns

set -e

# Check if Manager framework is available
check_manager() {
    # Check if manager is installed in the system
    if [ -d "/usr/local/lib/manager" ]; then
        MANAGER_DIR="/usr/local/lib/manager"
        return 0
    fi
    
    # Check if manager is in user's home
    if [ -d "$HOME/manager" ]; then
        MANAGER_DIR="$HOME/manager"
        return 0
    fi
    
    # Check if manager is in parent projects directory (workspace mode)
    if [ -d "../manager" ]; then
        MANAGER_DIR="../manager"
        return 0
    fi
    
    # Manager not found - need to clone it
    echo "Manager framework not found. Installing..."
    git clone https://github.com/akaoio/manager.git "$HOME/manager" || {
        echo "Failed to install Manager framework"
        exit 1
    }
    MANAGER_DIR="$HOME/manager"
}

# Load Manager framework
check_manager
. "$MANAGER_DIR/manager.sh"

# Display header
manager_header() {
    echo "=================================================="
    echo "  Access - Dynamic DNS IP Synchronization v2.1.0"
    echo "  Pure Shell | Multi-Provider | Manager-Powered"
    echo "=================================================="
    echo ""
}

# Main installation
main() {
    manager_header
    
    # Initialize Manager for Access
    manager_init "access" \
                 "https://github.com/akaoio/access.git" \
                 "access.sh" \
                 "Dynamic DNS IP Synchronization"
    
    # Parse command line arguments
    USE_SERVICE=false
    USE_CRON=false
    USE_AUTO_UPDATE=false
    USE_DISCOVERY=false
    CRON_INTERVAL=5
    SHOW_HELP=false
    
    for arg in "$@"; do
        case "$arg" in
            --service|--systemd)
                USE_SERVICE=true
                ;;
            --cron)
                USE_CRON=true
                ;;
            --auto-update)
                USE_AUTO_UPDATE=true
                ;;
            --discovery)
                USE_DISCOVERY=true
                ;;
            --interval=*)
                CRON_INTERVAL="${arg#*=}"
                USE_CRON=true
                ;;
            --redundant)
                USE_SERVICE=true
                USE_CRON=true
                ;;
            --help|-h)
                SHOW_HELP=true
                ;;
            *)
                manager_warn "Unknown option: $arg"
                ;;
        esac
    done
    
    if [ "$SHOW_HELP" = true ]; then
        cat << 'EOF'
Access Installation - Manager Framework Edition

Options:
  --service       Setup systemd service (system or user level)
  --cron          Setup cron job for periodic updates
  --interval=N    Cron interval in minutes (default: 5)
  --redundant     Both service and cron (recommended)
  --discovery     Enable network discovery for swarm mode
  --auto-update   Enable weekly auto-updates
  --help          Show this help

Examples:
  ./install-with-manager.sh --redundant --auto-update
  ./install-with-manager.sh --service --discovery
  ./install-with-manager.sh --cron --interval=10

The Manager framework handles:
  ✓ XDG-compliant directory creation
  ✓ Clean clone architecture
  ✓ Automatic sudo/non-sudo detection
  ✓ Systemd service creation (system or user)
  ✓ Cron job setup with proper scheduling
  ✓ Auto-update configuration
  ✓ Cross-platform package manager support

EOF
        exit 0
    fi
    
    # Build installation arguments
    INSTALL_ARGS=""
    [ "$USE_SERVICE" = true ] && INSTALL_ARGS="$INSTALL_ARGS --service"
    [ "$USE_CRON" = true ] && INSTALL_ARGS="$INSTALL_ARGS --cron --interval=$CRON_INTERVAL"
    [ "$USE_AUTO_UPDATE" = true ] && INSTALL_ARGS="$INSTALL_ARGS --auto-update"  # Manager handles this!
    
    # Default to cron if nothing specified
    if [ "$USE_SERVICE" = false ] && [ "$USE_CRON" = false ]; then
        manager_log "No automation specified, defaulting to cron job"
        INSTALL_ARGS="--cron"
    fi
    
    # Run Manager installation
    manager_log "Installing Access with Manager framework..."
    manager_install $INSTALL_ARGS || {
        manager_error "Installation failed"
        exit 1
    }
    
    # Handle Access-specific features
    if [ "$USE_DISCOVERY" = true ]; then
        setup_network_discovery
    fi
    
    # Setup Access configuration
    setup_access_config
    
    # Show completion summary
    show_summary
}

# Setup network discovery (Access-specific)
setup_network_discovery() {
    manager_log "Setting up network discovery..."
    
    # Copy discovery scripts to installation directory
    if [ -f "$MANAGER_CLEAN_CLONE_DIR/discovery.sh" ]; then
        discovery_dest="$MANAGER_INSTALL_DIR/access-discovery"
        
        if [ -w "$MANAGER_INSTALL_DIR" ]; then
            cp "$MANAGER_CLEAN_CLONE_DIR/discovery.sh" "$discovery_dest"
            chmod +x "$discovery_dest"
        else
            sudo cp "$MANAGER_CLEAN_CLONE_DIR/discovery.sh" "$discovery_dest"
            sudo chmod +x "$discovery_dest"
        fi
        
        manager_log "✓ Network discovery enabled"
        manager_log "  Command: access-discovery"
    fi
    
    # Setup discovery service if using systemd
    if [ "$USE_SERVICE" = true ]; then
        setup_discovery_service
    fi
}

# Setup discovery service
setup_discovery_service() {
    manager_log "Creating discovery service..."
    
    # Use Manager's service creation with custom unit
    SERVICE_NAME="access-discovery"
    SERVICE_DESCRIPTION="Access Network Discovery Service"
    SERVICE_EXEC="$MANAGER_INSTALL_DIR/access-discovery"
    
    # Manager handles sudo detection and user vs system service
    manager_create_service "$SERVICE_NAME" "$SERVICE_DESCRIPTION" "$SERVICE_EXEC"
}

# Setup Access configuration
setup_access_config() {
    manager_log "Setting up Access configuration..."
    
    # Config directory already created by Manager during installation
    
    # Check for existing configuration
    CONFIG_FILE="$MANAGER_CONFIG_DIR/config.json"
    
    if [ -f "$CONFIG_FILE" ]; then
        manager_log "✓ Existing configuration preserved"
    else
        manager_log "  Please run: access config <provider> --key=KEY --domain=DOMAIN"
    fi
}

# Show completion summary
show_summary() {
    echo ""
    echo "=================================================="
    echo "  Access Installation Complete (Manager-Powered)"
    echo "=================================================="
    echo ""
    
    echo "📁 File Locations (XDG Compliant via Manager):"
    echo "   Config:      ~/.config/access/config.json"
    echo "   Data & Logs: ~/.local/share/access/"
    echo "   State Files: ~/.local/state/access/"
    echo "   Clean Clone: ~/access/"
    echo ""
    
    echo "🚀 Quick Start:"
    echo "   access config godaddy --key=KEY --secret=SECRET --domain=example.com"
    echo "   access ip              # Detect current IP"
    echo "   access update          # Update DNS immediately"
    echo ""
    
    if [ "$USE_SERVICE" = true ]; then
        manager_show_service_commands "access"
    fi
    
    if [ "$USE_CRON" = true ]; then
        echo "⏰ Cron Job:"
        echo "   Updates every $CRON_INTERVAL minutes"
        echo "   View/edit: crontab -e"
        echo ""
    fi
    
    if [ "$USE_DISCOVERY" = true ]; then
        echo "🌐 Network Discovery:"
        echo "   access-discovery       # Find and claim peer slot"
        echo "   Swarm: peer0.akao.io, peer1.akao.io, ..."
        echo ""
    fi
    
    echo "Manager Framework Benefits:"
    echo "  ✓ Standardized installation across AKAO ecosystem"
    echo "  ✓ Automatic sudo/non-sudo detection"
    echo "  ✓ XDG-compliant directory structure"
    echo "  ✓ Cross-platform package manager support"
    echo "  ✓ Unified service management"
    echo "  ✓ Built-in auto-update system"
    echo ""
    
    manager_log "Access is ready!"
}

# Run main installation
main "$@"