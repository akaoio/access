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

# Interactive prompts for user preferences
interactive_setup() {
    manager_log "Welcome to Access installation!"
    echo ""
    
    # Ask about automation method
    echo "How would you like Access to run?"
    echo "  1) Systemd service (recommended for servers)"
    echo "  2) Cron job (recommended for personal use)"
    echo "  3) Both (redundant automation - most reliable)"
    echo "  4) Manual only (no automation)"
    printf "Choice (1-4): "
    read -r automation_choice
    
    case "$automation_choice" in
        1) USE_SERVICE=true ;;
        2) USE_CRON=true ;;
        3) USE_SERVICE=true; USE_CRON=true ;;
        4) ;;
        *) manager_warn "Invalid choice, defaulting to cron"; USE_CRON=true ;;
    esac
    
    # Ask about cron interval if using cron
    if [ "$USE_CRON" = true ]; then
        echo ""
        printf "Cron update interval in minutes? (default: 5): "
        read -r interval_input
        if [ -n "$interval_input" ] && [ "$interval_input" -gt 0 ] 2>/dev/null; then
            CRON_INTERVAL="$interval_input"
        fi
    fi
    
    # Ask about network discovery
    echo ""
    printf "Enable network discovery for peer detection? (y/N): "
    read -r discovery_choice
    case "$discovery_choice" in
        [yY]|[yY][eE][sS]) USE_DISCOVERY=true ;;
        *) USE_DISCOVERY=false ;;
    esac
    
    # Ask about auto-updates
    echo ""
    printf "Enable weekly auto-updates? (y/N): "
    read -r update_choice
    case "$update_choice" in
        [yY]|[yY][eE][sS]) USE_AUTO_UPDATE=true ;;
        *) USE_AUTO_UPDATE=false ;;
    esac
    
    echo ""
    manager_log "Configuration complete!"
    
    # Show summary of choices
    echo ""
    echo "Installation Summary:"
    if [ "$USE_SERVICE" = true ]; then
        echo "  ✓ Systemd service will be created"
    fi
    if [ "$USE_CRON" = true ]; then
        echo "  ✓ Cron job will run every $CRON_INTERVAL minutes"
    fi
    if [ "$USE_DISCOVERY" = true ]; then
        echo "  ✓ Network discovery will be enabled"
    fi
    if [ "$USE_AUTO_UPDATE" = true ]; then
        echo "  ✓ Weekly auto-updates will be enabled"
    fi
    if [ "$USE_SERVICE" = false ] && [ "$USE_CRON" = false ]; then
        echo "  • Manual operation only (no automation)"
    fi
    echo ""
    printf "Continue with installation? (Y/n): "
    read -r confirm
    case "$confirm" in
        [nN]|[nN][oO]) 
            manager_log "Installation cancelled by user"
            exit 0
            ;;
    esac
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
    INTERACTIVE=true
    
    for arg in "$@"; do
        case "$arg" in
            --service|--systemd)
                USE_SERVICE=true
                INTERACTIVE=false
                ;;
            --cron)
                USE_CRON=true
                INTERACTIVE=false
                ;;
            --auto-update)
                USE_AUTO_UPDATE=true
                INTERACTIVE=false
                ;;
            --discovery)
                USE_DISCOVERY=true
                INTERACTIVE=false
                ;;
            --interval=*)
                CRON_INTERVAL="${arg#*=}"
                USE_CRON=true
                INTERACTIVE=false
                ;;
            --redundant)
                USE_SERVICE=true
                USE_CRON=true
                INTERACTIVE=false
                ;;
            --non-interactive)
                INTERACTIVE=false
                ;;
            --help|-h)
                SHOW_HELP=true
                ;;
            *)
                manager_warn "Unknown option: $arg"
                ;;
        esac
    done
    
    # Run interactive setup if no command line args provided
    if [ "$INTERACTIVE" = true ] && [ "$SHOW_HELP" = false ]; then
        interactive_setup
    fi
    
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
  --non-interactive Skip interactive prompts (use with other options)
  --help          Show this help

Interactive Mode:
  Run without options for interactive setup with guided prompts

Examples:
  ./install.sh                    # Interactive setup (recommended)
  ./install.sh --redundant --auto-update
  ./install.sh --service --discovery
  ./install.sh --cron --interval=10
  ./install.sh --non-interactive --cron  # Non-interactive with defaults

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