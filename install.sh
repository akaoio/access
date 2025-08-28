#!/bin/sh
# Access installation using Stacker framework
# This replaces the complex install.sh with standardized Stacker patterns

set -e

# Support test mode for CI/CD
if [ "$1" = "--test-mode" ]; then
    TEST_MODE=true
    INSTALL_DIR="${TEST_INSTALL_DIR:-$HOME/test-access}"
    mkdir -p "$INSTALL_DIR"
else
    TEST_MODE=false
    INSTALL_DIR="$HOME/.local/bin"
fi


# Check if Stacker framework is available
check_stacker() {
    # For testing: use local modular manager
    local script_dir="$(dirname "$0")"
    if [ -f "$script_dir/stacker.sh" ]; then
        STACKER_DIR="$script_dir"
        return 0
    fi
    
    # Check if manager is in user's home (standard location)
    if [ -d "$HOME/stacker" ]; then
        STACKER_DIR="$HOME/stacker"
        return 0
    fi
    
    # Check if manager is installed in the system
    if [ -d "/usr/local/lib/stacker" ]; then
        STACKER_DIR="/usr/local/lib/stacker"
        return 0
    fi
    
    # Stacker not found - need to clone it
    echo "Stacker framework not found. Installing..."
    git clone https://github.com/akaoio/manager.git "$HOME/stacker" || {
        echo "Failed to install Stacker framework"
        exit 1
    }
    STACKER_DIR="$HOME/stacker"
    echo "Stacker framework installed successfully at $HOME/stacker"
}

# Load Stacker framework
check_stacker
. "$STACKER_DIR/stacker.sh"

# Display header
stacker_header() {
    echo "=================================================="
    echo "  Access - Dynamic DNS IP Synchronization v2.1.0"
    echo "  Pure Shell | Multi-Provider | Stacker-Powered"
    echo "=================================================="
    echo ""
}

# Interactive prompts for user preferences
interactive_setup() {
    stacker_log "Welcome to Access installation!"
    echo ""
    
    # Ask about automation method
    echo "Access will be installed with REDUNDANT AUTOMATION (both systemd + cron)"
    echo "This ensures maximum reliability - if one method fails, the other continues."
    echo ""
    echo "Default setup:"
    echo "  ✓ Systemd service (immediate start, system integration)"
    echo "  ✓ Cron job (backup automation, survives system changes)"
    echo ""
    printf "Continue with redundant automation? (Y/n): "
    read -r automation_choice
    
    case "$automation_choice" in
        [nN]|[nN][oO])
            echo ""
            echo "Manual automation selection:"
            echo "  1) Systemd service only"
            echo "  2) Cron job only"
            echo "  3) Both (redundant - recommended)"
            echo "  4) Manual only (no automation)"
            printf "Choice (1-4): "
            read -r manual_choice
            
            case "$manual_choice" in
                1) USE_SERVICE=true ;;
                2) USE_CRON=true ;;
                3) USE_SERVICE=true; USE_CRON=true ;;
                4) ;;
                *) stacker_warn "Invalid choice, using redundant automation"; USE_SERVICE=true; USE_CRON=true ;;
            esac
            ;;
        *)
            # Default: redundant automation (both service and cron)
            USE_SERVICE=true
            USE_CRON=true
            ;;
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
    
    # Ask about network scan
    echo ""
    printf "Enable network scan for peer detection? (y/N): "
    read -r scan_choice
    case "$scan_choice" in
        [yY]|[yY][eE][sS]) USE_SCAN=true ;;
        *) USE_SCAN=false ;;
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
    stacker_log "Configuration complete!"
    
    # Show summary of choices
    echo ""
    echo "Installation Summary:"
    if [ "$USE_SERVICE" = true ]; then
        echo "  ✓ Systemd service will be created"
    fi
    if [ "$USE_CRON" = true ]; then
        echo "  ✓ Cron job will run every $CRON_INTERVAL minutes"
    fi
    if [ "$USE_SCAN" = true ]; then
        echo "  ✓ Network scan will be enabled"
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
            stacker_log "Installation cancelled by user"
            exit 0
            ;;
    esac
}

# Main installation
main() {
    stacker_header
    
    # Initialize Stacker for Access
    stacker_init "access" \
                 "https://github.com/akaoio/access.git" \
                 "access.sh" \
                 "Dynamic DNS IP Synchronization"
    
    # Create XDG-compliant directory structure using Stacker
    stacker_create_xdg_dirs
    
    # Parse command line arguments
    # DEFAULT: Redundant automation (both systemd service and cron)
    USE_SERVICE=true
    USE_CRON=true
    USE_REDUNDANT=false
    USE_AUTO_UPDATE=false
    USE_SCAN=false
    CRON_INTERVAL=5
    SHOW_HELP=false
    INTERACTIVE=true
    
    for arg in "$@"; do
        case "$arg" in
            --service-only|--systemd-only)
                # Override default: systemd only
                USE_SERVICE=true
                USE_CRON=false
                INTERACTIVE=false
                ;;
            --service|--systemd)
                USE_SERVICE=true
                INTERACTIVE=false
                ;;
            --cron-only)
                # Override default: cron only
                USE_SERVICE=false
                USE_CRON=true
                INTERACTIVE=false
                ;;
            --cron)
                USE_CRON=true
                INTERACTIVE=false
                ;;
            --manual-only|--no-automation)
                # Override default: no automation
                USE_SERVICE=false
                USE_CRON=false
                INTERACTIVE=false
                ;;
            --auto-update)
                USE_AUTO_UPDATE=true
                INTERACTIVE=false
                ;;
            --scan)
                USE_SCAN=true
                INTERACTIVE=false
                ;;
            --interval=*)
                CRON_INTERVAL="${arg#*=}"
                USE_CRON=true
                INTERACTIVE=false
                ;;
            --redundant)
                USE_REDUNDANT=true
                INTERACTIVE=false
                ;;
            --non-interactive)
                INTERACTIVE=false
                ;;
            --help|-h)
                SHOW_HELP=true
                ;;
            *)
                stacker_warn "Unknown option: $arg"
                ;;
        esac
    done
    
    # Run interactive setup if no command line args provided
    if [ "$INTERACTIVE" = true ] && [ "$SHOW_HELP" = false ]; then
        interactive_setup
    fi
    
    if [ "$SHOW_HELP" = true ]; then
        cat << 'EOF'
Access Installation - Stacker Framework Edition

DEFAULT BEHAVIOR:
  Access installs with REDUNDANT AUTOMATION by default (both systemd + cron)
  This ensures maximum reliability - if one method fails, the other continues.

Automation Options:
  --service       Setup systemd service (adds to default)
  --cron          Setup cron job (adds to default)
  --service-only  Systemd service ONLY (overrides default)
  --cron-only     Cron job ONLY (overrides default)
  --manual-only   No automation (overrides default)
  --interval=N    Cron interval in minutes (default: 5)
  --redundant     Explicit redundant automation (same as default)

Additional Options:
  --scan          Enable network scan for swarm mode
  --auto-update   Enable weekly auto-updates
  --non-interactive Skip interactive prompts
  --help          Show this help

Interactive Mode:
  Run without options for default redundant automation with prompts

Examples:
  ./install.sh                    # Default: systemd + cron with prompts
  ./install.sh --non-interactive  # Default: systemd + cron without prompts
  ./install.sh --service-only     # Systemd service only
  ./install.sh --cron-only --interval=10  # Cron every 10 minutes only
  ./install.sh --manual-only      # No automation
  ./install.sh --auto-update      # Default + auto-updates

The Stacker framework handles:
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
    
    # Handle redundant automation setup using Stacker
    if [ "$USE_REDUNDANT" = true ]; then
        # Stacker's built-in redundant automation (both systemd + cron)
        INSTALL_ARGS="--redundant"
    else
        # Build installation arguments for single automation
        INSTALL_ARGS=""
        [ "$USE_SERVICE" = true ] && INSTALL_ARGS="$INSTALL_ARGS --service"
        [ "$USE_CRON" = true ] && INSTALL_ARGS="$INSTALL_ARGS --cron --interval=$CRON_INTERVAL"
        
        # Default to cron if nothing specified
        if [ "$USE_SERVICE" = false ] && [ "$USE_CRON" = false ] && [ "$USE_REDUNDANT" = false ]; then
            stacker_log "No automation specified, defaulting to cron job"
            INSTALL_ARGS="--cron"
        fi
    fi
    
    # Add auto-update if requested (Stacker handles this)
    [ "$USE_AUTO_UPDATE" = true ] && INSTALL_ARGS="$INSTALL_ARGS --auto-update"
    
    # Check and install dependencies using Stacker
    stacker_log "Checking system dependencies..."
    stacker_check_requirements "curl" "curl" || stacker_auto_install_deps "curl"
    stacker_check_requirements "dig" "bind-utils dnsutils" || stacker_auto_install_deps "bind-utils dnsutils"
    
    # Run Stacker installation (uses .stacker-config automatically)
    stacker_log "Installing Access with Stacker framework..."
    stacker_install $INSTALL_ARGS || {
        stacker_error "Installation failed"
        exit 1
    }
    
    # Verify installation using Stacker
    stacker_verify_installation || {
        stacker_warn "Installation verification failed - please check manually"
    }
    
    # Handle Access-specific features
    if [ "$USE_SCAN" = true ]; then
        setup_network_scan
    fi
    
    # Setup Access configuration using Stacker's config management
    setup_access_config
    
    # Check for updates immediately after installation
    stacker_check_updates || true
    
    # Show completion summary
    show_summary
    
    # For test mode, create symlink in expected location
    if [ "$TEST_MODE" = true ]; then
        ln -sf "$PWD/access.sh" "$INSTALL_DIR/access"
        echo "Test mode: Created symlink at $INSTALL_DIR/access"
    fi
}

# Setup network scan (simplified - files already installed by Stacker)
setup_network_scan() {
    stacker_log "Network scan enabled via Stacker framework"
    
    # Scan.sh is automatically installed by Stacker via .stacker-config
    # Just notify user that it's available
    if [ -x "$STACKER_INSTALL_DIR/scan" ]; then
        stacker_log "✓ Network scan available"
        stacker_log "  Command: scan"
    fi
    
    # Setup scan service if using systemd
    if [ "$USE_SERVICE" = true ]; then
        setup_scan_service
    fi
}

# Setup scan service
setup_scan_service() {
    stacker_log "Creating scan service..."
    
    # Configure scan service integration with Stacker framework
    if [ -f "./scan.sh" ]; then
        stacker_log "✓ Scan service integrated with Access"
        stacker_log "  Note: Scan runs alongside main Access service"
        
        # Ensure scan.sh is executable
        chmod +x ./scan.sh
        
        # Create scan service script if systemd installation
        if [ "$install_method" = "systemd" ]; then
            cat > "$STACKER_CONFIG_DIR/access-scan.service" << EOF
[Unit]
Description=Access Network Scanner
After=access.service
Requires=access.service

[Service]
Type=simple
ExecStart=$(pwd)/scan.sh --daemon
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
            stacker_log "✓ Scan service configuration created"
        fi
    else
        stacker_log "✓ Scan service not found, skipping integration"
    fi
}

# Setup Access configuration using Stacker's config management
setup_access_config() {
    stacker_log "Setting up Access configuration..."
    
    # Use Stacker's configuration management functions
    stacker_load_config || {
        # No existing config, create default
        stacker_create_default_config || true
        stacker_log "  Please run: access config <provider> --key=KEY --domain=DOMAIN"
    }
    
    # Load any environment variable overrides
    stacker_load_env_overrides
    
    # Check if provider is configured
    if stacker_get_config "provider" >/dev/null 2>&1; then
        local provider=$(stacker_get_config "provider")
        local domain=$(stacker_get_config "domain")
        stacker_log "✓ Existing configuration preserved"
        stacker_log "  Provider: $provider, Domain: $domain"
    else
        stacker_log "  Configuration required: access config <provider> --key=KEY --domain=DOMAIN"
    fi
}

# Show completion summary
show_summary() {
    echo ""
    echo "=================================================="
    echo "  Access Installation Complete (Stacker-Powered)"
    echo "=================================================="
    echo ""
    
    echo "📁 File Locations (XDG Compliant via Stacker):"
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
    
    # Use Stacker's built-in service command display
    stacker_status || true
    
    # Show additional commands based on what was installed
    echo "📝 Management Commands:"
    echo "   access --version       # Show version"
    echo "   access check-updates   # Check for updates"
    if [ "$USE_AUTO_UPDATE" = true ]; then
        echo "   access auto-update     # Manually trigger update"
    fi
    echo ""
    
    if [ "$USE_SCAN" = true ]; then
        echo "🌐 Network Scan:"
        echo "   access-scan       # Find and claim peer slot"
        echo "   Swarm: peer0.akao.io, peer1.akao.io, ..."
        echo ""
    fi
    
    echo "Stacker Framework Benefits:"
    echo "  ✓ Standardized installation across AKAO ecosystem"
    echo "  ✓ Automatic sudo/non-sudo detection"
    echo "  ✓ XDG-compliant directory structure"
    echo "  ✓ Cross-platform package manager support"
    echo "  ✓ Unified service management"
    echo "  ✓ Built-in auto-update system"
    echo ""
    
    stacker_log "Access is ready!"
}

# Run main installation
main "$@"