#!/bin/sh
# Access installer - Pure, safe, and trustworthy
# Supports both systemd service and cron with optional auto-update

set -e

# Configuration
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
REPO_URL="${REPO_URL:-https://github.com/akaoio/access.git}"
CLEAN_CLONE_DIR="$HOME/access"
SCRIPT_NAME="access"
VERSION="2.0.0"

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

log() {
    echo "${GREEN}[Access]${NC} $*"
}

warn() {
    echo "${YELLOW}[Warning]${NC} $*"
}

error() {
    echo "${RED}[Error]${NC} $*" >&2
}

# Display header
show_header() {
    echo "=================================================="
    echo "  Access - Dynamic DNS IP Synchronization v${VERSION}"
    echo "  Pure Shell | Multi-Provider | Clean Clone Install"
    echo "=================================================="
    echo ""
}

# Check for required tools
check_requirements() {
    local missing=""
    
    # Check for git (now required for clean clone)
    if ! command -v git >/dev/null 2>&1; then
        missing="$missing git"
    fi
    
    # Check for curl or wget (required)
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing="$missing curl/wget"
    fi
    
    # Check for DNS tools (optional but recommended)
    if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
        warn "No DNS tools found (dig/nslookup). HTTP detection will be used."
    fi
    
    if [ -n "$missing" ]; then
        error "Required tools missing:$missing"
        error "Please install them and try again."
        exit 1
    fi
}

# Create clean clone of Access repository
create_clean_clone() {
    log "Creating clean clone at $CLEAN_CLONE_DIR..."
    
    # Remove existing clone if present
    if [ -d "$CLEAN_CLONE_DIR" ]; then
        log "Removing existing Access clone..."
        rm -rf "$CLEAN_CLONE_DIR"
    fi
    
    # Clone fresh repository
    git clone "$REPO_URL" "$CLEAN_CLONE_DIR" || {
        error "Failed to clone Access repository from $REPO_URL"
        exit 1
    }
    
    # Verify access.sh exists in clean clone
    if [ ! -f "$CLEAN_CLONE_DIR/access.sh" ]; then
        error "Clean clone missing access.sh - repository structure may be incorrect"
        exit 1
    fi
    
    log "✓ Clean clone created successfully"
}

# Install script from clean clone
install_script() {
    local src="$CLEAN_CLONE_DIR/access.sh"
    local dest="$INSTALL_DIR/$SCRIPT_NAME"
    
    # Verify source exists
    if [ ! -f "$src" ]; then
        error "Source script not found at $src"
        exit 1
    fi
    
    # Check if we need sudo
    if [ -w "$INSTALL_DIR" ]; then
        cp "$src" "$dest"
        chmod +x "$dest"
    else
        log "Installing to $INSTALL_DIR (requires sudo)..."
        sudo cp "$src" "$dest"
        sudo chmod +x "$dest"
    fi
    
    # Create XDG-compliant config directory
    mkdir -p "$HOME/.config/access"
    
    log "✓ Access installed to $dest (from clean clone)"
}

# Setup systemd service
setup_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemd not available on this system"
        return 1
    fi
    
    log "Setting up systemd service..."
    
    # Create service file
    cat <<EOF | sudo tee /etc/systemd/system/access.service >/dev/null
[Unit]
Description=Access - Dynamic DNS IP Synchronization
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Environment="HOME=$HOME"
ExecStart=$INSTALL_DIR/$SCRIPT_NAME daemon
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$HOME/.config/access

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    
    log "✓ Systemd service created"
    log "  Commands:"
    log "    Start:   sudo systemctl start access"
    log "    Stop:    sudo systemctl stop access"
    log "    Status:  sudo systemctl status access"
    log "    Enable:  sudo systemctl enable access"
    log "    Logs:    sudo journalctl -u access -f"
    
    return 0
}

# Setup cron job
setup_cron() {
    local interval="${1:-5}"
    
    if ! command -v crontab >/dev/null 2>&1; then
        warn "cron not available on this system"
        return 1
    fi
    
    log "Setting up cron job (every $interval minutes)..."
    
    # Remove any existing access cron jobs
    (crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/$SCRIPT_NAME") | crontab - 2>/dev/null || true
    
    # Add new cron job with auto-update check
    local cron_line="*/$interval * * * * $INSTALL_DIR/$SCRIPT_NAME update >/dev/null 2>&1"
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    
    log "✓ Cron job created (runs every $interval minutes)"
    log "  Commands:"
    log "    View:    crontab -l"
    log "    Remove:  crontab -l | grep -v access | crontab -"
    
    return 0
}

# Setup auto-update with clean clone maintenance and XDG config
setup_auto_update() {
    log "Setting up auto-update with clean clone maintenance and XDG config..."
    
    # Create XDG-compliant config directory
    mkdir -p "$HOME/.config/access"
    
    # Create update script that uses ~/access and XDG paths
    cat > "$HOME/.config/access/auto-update.sh" <<EOF
#!/bin/sh
# Access auto-update script - Uses ~/access folder and XDG config

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="access"
REPO_URL="https://github.com/akaoio/access.git"
CLEAN_CLONE_DIR="$HOME/access"
CURRENT="\$INSTALL_DIR/\$SCRIPT_NAME"
CONFIG_DIR="$HOME/.config/access"
LOG_FILE="\$CONFIG_DIR/auto-update.log"

# Function to log with timestamp
log_update() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE"
}

# Function to update clean clone
update_clean_clone() {
    if [ -d "\$CLEAN_CLONE_DIR" ]; then
        cd "\$CLEAN_CLONE_DIR" || {
            log_update "ERROR: Cannot cd to \$CLEAN_CLONE_DIR"
            return 1
        }
        
        git fetch origin main >/dev/null 2>&1 || {
            log_update "ERROR: git fetch failed"
            return 1
        }
        
        # Check if update needed
        LOCAL=\$(git rev-parse HEAD 2>/dev/null)
        REMOTE=\$(git rev-parse origin/main 2>/dev/null)
        
        if [ "\$LOCAL" != "\$REMOTE" ]; then
            git reset --hard origin/main >/dev/null 2>&1 || {
                log_update "ERROR: git reset failed"
                return 1
            }
            log_update "Clean clone updated from \${LOCAL:0:8} to \${REMOTE:0:8}"
            return 0
        else
            log_update "Clean clone already up to date (\${LOCAL:0:8})"
            return 1
        fi
    else
        # Clone if directory doesn't exist
        log_update "Clean clone missing, creating \$CLEAN_CLONE_DIR"
        git clone "\$REPO_URL" "\$CLEAN_CLONE_DIR" >/dev/null 2>&1 || {
            log_update "ERROR: git clone failed"
            return 1
        }
        log_update "Clean clone created successfully"
        return 0
    fi
}

# Update clean clone first
if update_clean_clone; then
    # Install from updated clean clone
    SRC="\$CLEAN_CLONE_DIR/access.sh"
    if [ -f "\$SRC" ]; then
        # Backup current version with timestamp
        BACKUP="\$CURRENT.backup.\$(date +%Y%m%d-%H%M%S)"
        cp "\$CURRENT" "\$BACKUP" 2>/dev/null && log_update "Backed up to \$BACKUP"
        
        # Install new version from clean clone
        if [ -w "\$INSTALL_DIR" ]; then
            cp "\$SRC" "\$CURRENT" && chmod +x "\$CURRENT"
        else
            sudo cp "\$SRC" "\$CURRENT" && sudo chmod +x "\$CURRENT"
        fi
        
        if [ \$? -eq 0 ]; then
            log_update "Access updated successfully from clean clone"
            # Test the new installation
            if "\$CURRENT" version >/dev/null 2>&1; then
                log_update "New version verified working"
            else
                log_update "WARNING: New version test failed"
            fi
        else
            log_update "ERROR: Failed to install from clean clone"
        fi
    else
        log_update "ERROR: access.sh not found in clean clone at \$SRC"
    fi
else
    log_update "No updates needed"
fi
EOF
    
    chmod +x "$HOME/.config/access/auto-update.sh"
    
    # Add weekly auto-update cron job using XDG path
    local update_cron="0 3 * * 0 $HOME/.config/access/auto-update.sh >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "auto-update.sh"; echo "$update_cron") | crontab -
    
    log "✓ Auto-update enabled with clean clone maintenance and XDG config"
    log "  Update script: ~/.config/access/auto-update.sh"
    log "  Update log: ~/.config/access/auto-update.log" 
    log "  Clean clone: ~/access (used for all updates)"
    
    return 0
}

# Provider setup helper
show_provider_help() {
    cat <<'EOF'

Quick Start - Provider Configuration:
====================================

Configuration is stored in XDG-compliant directory: ~/.config/access/

1. GoDaddy:
   access config godaddy \
     --key=YOUR_API_KEY \
     --secret=YOUR_API_SECRET \
     --domain=example.com

2. Cloudflare:
   access config cloudflare \
     --email=your@email.com \
     --api-key=YOUR_API_KEY \
     --zone-id=YOUR_ZONE_ID \
     --domain=example.com

3. DigitalOcean:
   access config digitalocean \
     --token=YOUR_API_TOKEN \
     --domain=example.com

4. Azure DNS:
   access config azure \
     --subscription-id=YOUR_SUBSCRIPTION_ID \
     --resource-group=YOUR_RESOURCE_GROUP \
     --tenant-id=YOUR_TENANT_ID \
     --client-id=YOUR_CLIENT_ID \
     --client-secret=YOUR_CLIENT_SECRET \
     --domain=example.com

5. Google Cloud DNS:
   access config gcloud \
     --project-id=YOUR_PROJECT_ID \
     --zone-name=YOUR_ZONE_NAME \
     --service-account-key=YOUR_BASE64_KEY \
     --domain=example.com

6. AWS Route53:
   access config route53 \
     --zone-id=YOUR_HOSTED_ZONE_ID \
     --access-key=YOUR_ACCESS_KEY \
     --secret-key=YOUR_SECRET_KEY \
     --domain=example.com

Testing:
========
   access ip         # Test IP detection
   access update     # Test DNS update

File Locations:
===============
   Config:        ~/.config/access/config.json
   Update Log:    ~/.config/access/auto-update.log
   Clean Clone:   ~/access/ (used for self-updates)

EOF
}

# Parse arguments
parse_args() {
    USE_SYSTEMD=false
    USE_CRON=false
    USE_AUTO_UPDATE=false
    CRON_INTERVAL=5
    SHOW_HELP=false
    
    # If no args, default to cron
    if [ $# -eq 0 ]; then
        USE_CRON=true
        return
    fi
    
    for arg in "$@"; do
        case "$arg" in
            --systemd|--service)
                USE_SYSTEMD=true
                ;;
            --cron)
                USE_CRON=true
                ;;
            --auto-update)
                USE_AUTO_UPDATE=true
                ;;
            --interval=*)
                CRON_INTERVAL="${arg#*=}"
                USE_CRON=true
                ;;
            --help|-h)
                SHOW_HELP=true
                ;;
            *)
                warn "Unknown option: $arg"
                ;;
        esac
    done
    
    # If neither specified, default to cron
    if [ "$USE_SYSTEMD" = false ] && [ "$USE_CRON" = false ] && [ "$SHOW_HELP" = false ]; then
        USE_CRON=true
    fi
}

# Show help
show_help() {
    show_header
    cat <<'EOF'
Installation Options:
====================

  --systemd        Install systemd service
  --service        Alias for --systemd
  --cron           Install cron job (default)
  --interval=N     Set cron interval in minutes (default: 5)
  --auto-update    Enable weekly auto-updates
  --help           Show this help

Examples:
=========

  # Default installation (cron every 5 minutes)
  ./install.sh

  # Systemd service
  ./install.sh --systemd

  # Cron with custom interval
  ./install.sh --cron --interval=10

  # Both systemd and cron with auto-update
  ./install.sh --systemd --cron --auto-update

  # Everything
  ./install.sh --systemd --cron --interval=3 --auto-update

EOF
    exit 0
}

# Main installation
main() {
    # Parse arguments
    parse_args "$@"
    
    # Show help if requested
    if [ "$SHOW_HELP" = true ]; then
        show_help
    fi
    
    # Show header
    show_header
    
    # Check requirements
    check_requirements
    
    # Create clean clone first (mandatory)
    create_clean_clone
    
    # Install script from clean clone
    install_script
    
    echo ""
    
    # Setup systemd if requested
    if [ "$USE_SYSTEMD" = true ]; then
        setup_systemd || warn "Failed to setup systemd service"
        echo ""
    fi
    
    # Setup cron if requested
    if [ "$USE_CRON" = true ]; then
        setup_cron "$CRON_INTERVAL" || warn "Failed to setup cron job"
        echo ""
    fi
    
    # Setup auto-update if requested
    if [ "$USE_AUTO_UPDATE" = true ]; then
        setup_auto_update
        echo ""
    fi
    
    # Show completion message
    log "Installation complete!"
    echo "=================================================="
    
    # Show provider help
    show_provider_help
}

# Run main
main "$@"