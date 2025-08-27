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

# Auto-install missing dependencies
auto_install_deps() {
    log "🔧 Attempting to install missing dependencies..."
    
    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        log "Detected apt package manager (Debian/Ubuntu)"
        if [ -n "$1" ]; then
            log "Installing: $1"
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y $1 >/dev/null 2>&1 || return 1
        fi
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS/Fedora
        log "Detected yum package manager (RHEL/CentOS)"
        if [ -n "$1" ]; then
            log "Installing: $1"
            sudo yum install -y $1 >/dev/null 2>&1 || return 1
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora 22+
        log "Detected dnf package manager (Fedora)"
        if [ -n "$1" ]; then
            log "Installing: $1"
            sudo dnf install -y $1 >/dev/null 2>&1 || return 1
        fi
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        log "Detected apk package manager (Alpine)"
        if [ -n "$1" ]; then
            log "Installing: $1"
            sudo apk add --no-cache $1 >/dev/null 2>&1 || return 1
        fi
    elif command -v brew >/dev/null 2>&1; then
        # macOS with Homebrew
        log "Detected brew package manager (macOS)"
        if [ -n "$1" ]; then
            log "Installing: $1"
            brew install $1 >/dev/null 2>&1 || return 1
        fi
    else
        error "No supported package manager found"
        return 1
    fi
    
    log "✓ Dependencies installed successfully"
    return 0
}

# Check for required tools
check_requirements() {
    local missing=""
    local missing_packages=""
    
    # Check for git (now required for clean clone)
    if ! command -v git >/dev/null 2>&1; then
        missing="$missing git"
        missing_packages="$missing_packages git"
    fi
    
    # Check for curl or wget (required)
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing="$missing curl/wget"
        missing_packages="$missing_packages curl"
    fi
    
    # Check for DNS tools (optional but recommended)
    if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
        warn "No DNS tools found (dig/nslookup). HTTP detection will be used."
        warn "To install: sudo apt-get install dnsutils (or bind-utils on RHEL)"
    fi
    
    if [ -n "$missing" ]; then
        error "Required tools missing:$missing"
        
        # Ask to auto-install if we have sudo
        if sudo -n true 2>/dev/null; then
            printf "Would you like to auto-install missing dependencies? [Y/n]: "
            read -r AUTO_INSTALL
            if [ "$AUTO_INSTALL" != "n" ] && [ "$AUTO_INSTALL" != "N" ]; then
                if auto_install_deps "$missing_packages"; then
                    log "✓ Dependencies installed. Continuing installation..."
                else
                    error "Failed to install dependencies automatically"
                    error "Please install manually: $missing"
                    exit 1
                fi
            else
                error "Please install manually: $missing"
                exit 1
            fi
        else
            error "Please install them and try again:"
            error "  Debian/Ubuntu: sudo apt-get install$missing_packages"
            error "  RHEL/CentOS: sudo yum install$missing_packages"
            error "  Alpine: sudo apk add$missing_packages"
            error "  macOS: brew install$missing_packages"
            exit 1
        fi
    fi
}

# Create clean clone of Access repository
create_clean_clone() {
    log "Creating clean clone at $CLEAN_CLONE_DIR..."
    
    current_dir=$(pwd)
    
    # SMART UPDATE: If running from target directory, update in place instead of deleting
    if [ "$current_dir" = "$CLEAN_CLONE_DIR" ]; then
        log "Running from Access directory - updating in place with git..."
        
        # Check if this is a git repository
        if [ -d ".git" ]; then
            log "Updating existing repository..."
            git fetch origin main || {
                error "Failed to fetch updates from $REPO_URL"
                exit 1
            }
            
            # Reset to latest version
            git reset --hard origin/main || {
                error "Failed to reset to latest version"
                exit 1
            }
            
            log "✓ Repository updated to latest version"
        else
            error "Current directory is not a git repository"
            error "Cannot update in place - please run from different location"
            exit 1
        fi
        
        # Set clean clone dir to current directory for installation
        CLEAN_CLONE_DIR="$current_dir"
        return 0
    fi
    
    # Normal clean clone for external installation
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

# Install script and dependencies from clean clone
install_script() {
    local src="$CLEAN_CLONE_DIR/access.sh"
    local dest="$INSTALL_DIR/$SCRIPT_NAME"
    
    # Verify source exists
    if [ ! -f "$src" ]; then
        error "Source script not found at $src"
        exit 1
    fi
    
    log "Installing Access with all provider dependencies..."
    
    # Ensure installation directory exists
    if [ ! -d "$INSTALL_DIR" ]; then
        log "Creating installation directory: $INSTALL_DIR"
        if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
            log "✓ Installation directory created"
        else
            log "Creating installation directory with sudo..."
            sudo mkdir -p "$INSTALL_DIR"
        fi
    fi
    
    # Install main script
    if [ -w "$INSTALL_DIR" ]; then
        cp "$src" "$dest"
        chmod +x "$dest"
    else
        log "Installing to $INSTALL_DIR (requires sudo)..."
        sudo cp "$src" "$dest"
        sudo chmod +x "$dest"
    fi
    
    # Install provider abstraction files
    local provider_files="provider-agnostic.sh provider.sh"
    for provider_file in $provider_files; do
        if [ -f "$CLEAN_CLONE_DIR/$provider_file" ]; then
            local provider_dest="$INSTALL_DIR/$provider_file"
            if [ -w "$INSTALL_DIR" ]; then
                cp "$CLEAN_CLONE_DIR/$provider_file" "$provider_dest"
                chmod +x "$provider_dest"
            else
                sudo cp "$CLEAN_CLONE_DIR/$provider_file" "$provider_dest"
                sudo chmod +x "$provider_dest"
            fi
            log "✓ Installed $provider_file"
        fi
    done
    
    # Install providers directory if it exists
    if [ -d "$CLEAN_CLONE_DIR/providers" ]; then
        local providers_dest="$INSTALL_DIR/providers"
        if [ -w "$INSTALL_DIR" ]; then
            cp -r "$CLEAN_CLONE_DIR/providers" "$providers_dest"
            chmod -R +x "$providers_dest"/*.sh 2>/dev/null || true
        else
            sudo cp -r "$CLEAN_CLONE_DIR/providers" "$providers_dest"
            sudo chmod -R +x "$providers_dest"/*.sh 2>/dev/null || true
        fi
        log "✓ Installed providers directory"
    fi
    
    # Create XDG-compliant config directory
    mkdir -p "$HOME/.config/access"
    
    log "✓ Access installed to $dest with all dependencies (from clean clone)"
}

# Setup systemd service
setup_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemd not available on this system"
        return 1
    fi
    
    log "Setting up systemd service..."
    
    # Check if we have sudo access or should use user service
    if sudo -n true 2>/dev/null; then
        # System-level service (requires sudo)
        log "Creating system-level service (requires sudo)..."
        
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
ReadWritePaths=$HOME/.config/access $HOME/.local/share/access $HOME/.access

[Install]
WantedBy=multi-user.target
EOF
        
        # Reload systemd and enable service
        sudo systemctl daemon-reload
        sudo systemctl enable access
        
        log "✓ System-level service created and enabled"
        log "  Commands:"
        log "    Start:   sudo systemctl start access"
        log "    Stop:    sudo systemctl stop access"
        log "    Status:  sudo systemctl status access"
        log "    Logs:    sudo journalctl -u access -f"
        
    else
        # User-level service (no sudo required)
        log "Creating user-level service (no sudo required)..."
        
        # Create user systemd directory if needed
        mkdir -p "$HOME/.config/systemd/user"
        
        cat <<EOF > "$HOME/.config/systemd/user/access.service"
[Unit]
Description=Access - Dynamic DNS IP Synchronization (User Service)
After=network.target

[Service]
Type=simple
Environment="HOME=$HOME"
ExecStart=$INSTALL_DIR/$SCRIPT_NAME daemon
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
        
        # Reload user systemd and enable service
        systemctl --user daemon-reload
        systemctl --user enable access
        
        # Start the service immediately after installation
        systemctl --user start access || {
            warn "Failed to start Access service - you may need to start it manually"
        }
        
        log "✓ User-level service created, enabled, and started"
        log "  Commands:"
        log "    Start:   systemctl --user start access"
        log "    Stop:    systemctl --user stop access"
        log "    Status:  systemctl --user status access"
        log "    Logs:    journalctl --user -u access -f"
        
        # Enable lingering so service starts at boot even without login
        if command -v loginctl >/dev/null 2>&1; then
            if sudo -n loginctl enable-linger "$USER" 2>/dev/null; then
                log "✓ User lingering enabled (service will start at boot)"
            else
                warn "Could not enable user lingering - service won't start at boot without login"
            fi
        fi
    fi
    
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

INSTALL_DIR="$INSTALL_DIR"
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
    # Install from updated clean clone with all dependencies
    SRC="\$CLEAN_CLONE_DIR/access.sh"
    if [ -f "\$SRC" ]; then
        log_update "Installing updated Access with all dependencies..."
        
        # Backup current version with timestamp
        BACKUP="\$CURRENT.backup.\$(date +%Y%m%d-%H%M%S)"
        cp "\$CURRENT" "\$BACKUP" 2>/dev/null && log_update "Backed up to \$BACKUP"
        
        # Install main script
        if [ -w "\$INSTALL_DIR" ]; then
            cp "\$SRC" "\$CURRENT" && chmod +x "\$CURRENT"
        else
            sudo cp "\$SRC" "\$CURRENT" && sudo chmod +x "\$CURRENT"
        fi
        
        # Install provider abstraction files
        PROVIDER_FILES="provider-agnostic.sh provider.sh"
        for provider_file in \$PROVIDER_FILES; do
            if [ -f "\$CLEAN_CLONE_DIR/\$provider_file" ]; then
                PROVIDER_DEST="\$INSTALL_DIR/\$provider_file"
                if [ -w "\$INSTALL_DIR" ]; then
                    cp "\$CLEAN_CLONE_DIR/\$provider_file" "\$PROVIDER_DEST"
                    chmod +x "\$PROVIDER_DEST"
                else
                    sudo cp "\$CLEAN_CLONE_DIR/\$provider_file" "\$PROVIDER_DEST"
                    sudo chmod +x "\$PROVIDER_DEST"
                fi
                log_update "Updated \$provider_file"
            fi
        done
        
        # Update providers directory if it exists
        if [ -d "\$CLEAN_CLONE_DIR/providers" ]; then
            PROVIDERS_DEST="\$INSTALL_DIR/providers"
            if [ -w "\$INSTALL_DIR" ]; then
                rm -rf "\$PROVIDERS_DEST" 2>/dev/null || true
                cp -r "\$CLEAN_CLONE_DIR/providers" "\$PROVIDERS_DEST"
                chmod -R +x "\$PROVIDERS_DEST"/*.sh 2>/dev/null || true
            else
                sudo rm -rf "\$PROVIDERS_DEST" 2>/dev/null || true
                sudo cp -r "\$CLEAN_CLONE_DIR/providers" "\$PROVIDERS_DEST"
                sudo chmod -R +x "\$PROVIDERS_DEST"/*.sh 2>/dev/null || true
            fi
            log_update "Updated providers directory"
        fi
        
        if [ \$? -eq 0 ]; then
            log_update "Access updated successfully with all dependencies from clean clone"
            # Test the new installation
            if "\$CURRENT" version >/dev/null 2>&1; then
                log_update "New version verified working"
                # Test provider loading
                if "\$CURRENT" providers >/dev/null 2>&1; then
                    log_update "Provider system verified working"
                else
                    log_update "WARNING: Provider system test failed"
                fi
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

# Setup network discovery
setup_network_discovery() {
    local mode="${1:-interactive}"
    
    log "Setting up network discovery and auto-sync..."
    
    # Install discovery module
    if [ -f "$CLEAN_CLONE_DIR/discovery.sh" ]; then
        local discovery_dest="$INSTALL_DIR/access-discovery"
        if [ -w "$INSTALL_DIR" ]; then
            cp "$CLEAN_CLONE_DIR/discovery.sh" "$discovery_dest"
            chmod +x "$discovery_dest"
        else
            sudo cp "$CLEAN_CLONE_DIR/discovery.sh" "$discovery_dest"
            sudo chmod +x "$discovery_dest"
        fi
        log "✓ Discovery module installed"
        
        # Run discovery setup
        if [ "$mode" = "interactive" ]; then
            "$discovery_dest" setup
        else
            # Non-interactive mode using environment variables
            export ACCESS_DISCOVERY_DOMAIN="${DISCOVERY_DOMAIN:-akao.io}"
            export ACCESS_DISCOVERY_PREFIX="${DISCOVERY_PREFIX:-peer}"
            export ACCESS_DNS_PROVIDER="$PROVIDER"
            export ACCESS_DNS_KEY="$PROVIDER_KEY"
            export ACCESS_DNS_SECRET="$PROVIDER_SECRET"
            export ACCESS_CLOUDFLARE_EMAIL="$PROVIDER_EMAIL"
            export ACCESS_CLOUDFLARE_ZONE_ID="$PROVIDER_ZONE_ID"
            
            "$discovery_dest" setup
        fi
        
        # Setup discovery daemon as systemd service
        if command -v systemctl >/dev/null 2>&1; then
            setup_discovery_service
        else
            # Setup as cron job for monitoring
            setup_discovery_cron
        fi
        
        return 0
    else
        warn "Discovery module not found in repository"
        return 1
    fi
}

# Setup discovery systemd service
setup_discovery_service() {
    log "Setting up discovery monitoring service..."
    
    if sudo -n true 2>/dev/null; then
        # System-level service
        cat <<EOF | sudo tee /etc/systemd/system/access-discovery.service >/dev/null
[Unit]
Description=Access Network Discovery and Self-Healing
After=network.target network-online.target access.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
Environment="HOME=$HOME"
ExecStart=$INSTALL_DIR/access-discovery daemon
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        sudo systemctl enable access-discovery
        sudo systemctl start access-discovery
        
        log "✓ Discovery service enabled and started"
    else
        # User-level service
        mkdir -p "$HOME/.config/systemd/user"
        
        cat <<EOF > "$HOME/.config/systemd/user/access-discovery.service"
[Unit]
Description=Access Network Discovery and Self-Healing (User Service)
After=network.target access.service

[Service]
Type=simple
Environment="HOME=$HOME"
ExecStart=$INSTALL_DIR/access-discovery daemon
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
        
        systemctl --user daemon-reload
        systemctl --user enable access-discovery
        systemctl --user start access-discovery
        
        log "✓ User discovery service enabled and started"
    fi
}

# Setup discovery cron job
setup_discovery_cron() {
    log "Setting up discovery monitoring cron job..."
    
    # Run discovery check every 5 minutes
    local cron_line="*/5 * * * * $INSTALL_DIR/access-discovery monitor >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "access-discovery"; echo "$cron_line") | crontab -
    
    log "✓ Discovery cron job created"
}

# Configure provider from flags
configure_provider_from_flags() {
    if [ -z "$PROVIDER" ]; then
        return 0  # No provider specified
    fi
    
    log "Configuring $PROVIDER provider from command line flags..."
    
    case "$PROVIDER" in
        godaddy)
            if [ -z "$PROVIDER_KEY" ] || [ -z "$PROVIDER_SECRET" ] || [ -z "$PROVIDER_DOMAIN" ]; then
                error "GoDaddy requires --key, --secret, and --domain"
                exit 1
            fi
            "$INSTALL_DIR/$SCRIPT_NAME" config godaddy \
                --key="$PROVIDER_KEY" \
                --secret="$PROVIDER_SECRET" \
                --domain="$PROVIDER_DOMAIN" \
                --host="$PROVIDER_HOST"
            ;;
        cloudflare)
            if [ -z "$PROVIDER_EMAIL" ] || [ -z "$PROVIDER_KEY" ] || [ -z "$PROVIDER_ZONE_ID" ] || [ -z "$PROVIDER_DOMAIN" ]; then
                error "Cloudflare requires --email, --key, --zone-id, and --domain"
                exit 1
            fi
            "$INSTALL_DIR/$SCRIPT_NAME" config cloudflare \
                --email="$PROVIDER_EMAIL" \
                --api-key="$PROVIDER_KEY" \
                --zone-id="$PROVIDER_ZONE_ID" \
                --domain="$PROVIDER_DOMAIN" \
                --host="$PROVIDER_HOST"
            ;;
        digitalocean)
            if [ -z "$PROVIDER_TOKEN" ] || [ -z "$PROVIDER_DOMAIN" ]; then
                error "DigitalOcean requires --token and --domain"
                exit 1
            fi
            "$INSTALL_DIR/$SCRIPT_NAME" config digitalocean \
                --token="$PROVIDER_TOKEN" \
                --domain="$PROVIDER_DOMAIN" \
                --host="$PROVIDER_HOST"
            ;;
        azure)
            if [ -z "$PROVIDER_SUBSCRIPTION_ID" ] || [ -z "$PROVIDER_RESOURCE_GROUP" ] || \
               [ -z "$PROVIDER_TENANT_ID" ] || [ -z "$PROVIDER_CLIENT_ID" ] || \
               [ -z "$PROVIDER_CLIENT_SECRET" ] || [ -z "$PROVIDER_DOMAIN" ]; then
                error "Azure requires --subscription-id, --resource-group, --tenant-id, --client-id, --client-secret, and --domain"
                exit 1
            fi
            "$INSTALL_DIR/$SCRIPT_NAME" config azure \
                --subscription-id="$PROVIDER_SUBSCRIPTION_ID" \
                --resource-group="$PROVIDER_RESOURCE_GROUP" \
                --tenant-id="$PROVIDER_TENANT_ID" \
                --client-id="$PROVIDER_CLIENT_ID" \
                --client-secret="$PROVIDER_CLIENT_SECRET" \
                --domain="$PROVIDER_DOMAIN" \
                --host="$PROVIDER_HOST"
            ;;
        gcloud)
            if [ -z "$PROVIDER_PROJECT_ID" ] || [ -z "$PROVIDER_ZONE_NAME" ] || \
               [ -z "$PROVIDER_SERVICE_ACCOUNT_KEY" ] || [ -z "$PROVIDER_DOMAIN" ]; then
                error "Google Cloud requires --project-id, --zone-name, --service-account-key, and --domain"
                exit 1
            fi
            "$INSTALL_DIR/$SCRIPT_NAME" config gcloud \
                --project-id="$PROVIDER_PROJECT_ID" \
                --zone-name="$PROVIDER_ZONE_NAME" \
                --service-account-key="$PROVIDER_SERVICE_ACCOUNT_KEY" \
                --domain="$PROVIDER_DOMAIN" \
                --host="$PROVIDER_HOST"
            ;;
        route53)
            if [ -z "$PROVIDER_ZONE_ID" ] || [ -z "$PROVIDER_ACCESS_KEY" ] || \
               [ -z "$PROVIDER_SECRET_KEY" ] || [ -z "$PROVIDER_DOMAIN" ]; then
                error "Route53 requires --zone-id, --access-key, --secret-key, and --domain"
                exit 1
            fi
            "$INSTALL_DIR/$SCRIPT_NAME" config route53 \
                --zone-id="$PROVIDER_ZONE_ID" \
                --access-key="$PROVIDER_ACCESS_KEY" \
                --secret-key="$PROVIDER_SECRET_KEY" \
                --domain="$PROVIDER_DOMAIN" \
                --host="$PROVIDER_HOST"
            ;;
        *)
            error "Unknown provider: $PROVIDER"
            error "Supported providers: godaddy, cloudflare, digitalocean, azure, gcloud, route53"
            exit 1
            ;;
    esac
    
    log "✓ $PROVIDER provider configured successfully"
}

# Interactive TUI setup
interactive_setup() {
    echo ""
    log "🎯 Interactive Access Configuration"
    echo "======================================"
    echo ""
    
    # Provider selection
    echo "Select your DNS provider:"
    echo "  1) GoDaddy"
    echo "  2) Cloudflare" 
    echo "  3) DigitalOcean"
    echo "  4) Azure DNS"
    echo "  5) Google Cloud DNS"
    echo "  6) AWS Route53"
    echo "  0) Skip provider configuration"
    echo ""
    printf "Choice [1-6, 0 to skip]: "
    read -r PROVIDER_CHOICE
    
    case "$PROVIDER_CHOICE" in
        1)
            interactive_godaddy
            ;;
        2)
            interactive_cloudflare
            ;;
        3)
            interactive_digitalocean
            ;;
        4)
            interactive_azure
            ;;
        5)
            interactive_gcloud
            ;;
        6)
            interactive_route53
            ;;
        0)
            log "Skipping provider configuration - you can configure later with:"
            log "  access config <provider> [options]"
            ;;
        *)
            warn "Invalid choice, skipping provider configuration"
            ;;
    esac
    
    echo ""
    log "✓ Interactive setup complete!"
}

# Interactive GoDaddy setup
interactive_godaddy() {
    echo ""
    log "📝 GoDaddy Configuration"
    echo "------------------------"
    
    printf "API Key: "
    read -r PROVIDER_KEY
    printf "API Secret: "
    read -r PROVIDER_SECRET
    printf "Domain (e.g., example.com): "
    read -r PROVIDER_DOMAIN
    printf "Host record [@ for root domain]: "
    read -r PROVIDER_HOST
    PROVIDER_HOST="${PROVIDER_HOST:-@}"
    
    if [ -n "$PROVIDER_KEY" ] && [ -n "$PROVIDER_SECRET" ] && [ -n "$PROVIDER_DOMAIN" ]; then
        "$INSTALL_DIR/$SCRIPT_NAME" config godaddy \
            --key="$PROVIDER_KEY" \
            --secret="$PROVIDER_SECRET" \
            --domain="$PROVIDER_DOMAIN" \
            --host="$PROVIDER_HOST"
        log "✓ GoDaddy configured successfully"
    else
        warn "Missing required fields, skipping configuration"
    fi
}

# Interactive Cloudflare setup
interactive_cloudflare() {
    echo ""
    log "📝 Cloudflare Configuration"
    echo "----------------------------"
    
    printf "Email: "
    read -r PROVIDER_EMAIL
    printf "API Key: "
    read -r PROVIDER_KEY
    printf "Zone ID: "
    read -r PROVIDER_ZONE_ID
    printf "Domain (e.g., example.com): "
    read -r PROVIDER_DOMAIN
    printf "Host record [@ for root domain]: "
    read -r PROVIDER_HOST
    PROVIDER_HOST="${PROVIDER_HOST:-@}"
    
    if [ -n "$PROVIDER_EMAIL" ] && [ -n "$PROVIDER_KEY" ] && [ -n "$PROVIDER_ZONE_ID" ] && [ -n "$PROVIDER_DOMAIN" ]; then
        "$INSTALL_DIR/$SCRIPT_NAME" config cloudflare \
            --email="$PROVIDER_EMAIL" \
            --api-key="$PROVIDER_KEY" \
            --zone-id="$PROVIDER_ZONE_ID" \
            --domain="$PROVIDER_DOMAIN" \
            --host="$PROVIDER_HOST"
        log "✓ Cloudflare configured successfully"
    else
        warn "Missing required fields, skipping configuration"
    fi
}

# Interactive DigitalOcean setup
interactive_digitalocean() {
    echo ""
    log "📝 DigitalOcean Configuration"
    echo "------------------------------"
    
    printf "API Token: "
    read -r PROVIDER_TOKEN
    printf "Domain (e.g., example.com): "
    read -r PROVIDER_DOMAIN
    printf "Host record [@ for root domain]: "
    read -r PROVIDER_HOST
    PROVIDER_HOST="${PROVIDER_HOST:-@}"
    
    if [ -n "$PROVIDER_TOKEN" ] && [ -n "$PROVIDER_DOMAIN" ]; then
        "$INSTALL_DIR/$SCRIPT_NAME" config digitalocean \
            --token="$PROVIDER_TOKEN" \
            --domain="$PROVIDER_DOMAIN" \
            --host="$PROVIDER_HOST"
        log "✓ DigitalOcean configured successfully"
    else
        warn "Missing required fields, skipping configuration"
    fi
}

# Enhanced visual setup menu with all options
enhanced_setup_menu() {
    echo ""
    echo "🚀 ACCESS SETUP WIZARD"
    echo "======================"
    echo ""
    echo "Choose additional features to enable:"
    echo ""
    echo "1. 🔄 AUTO-UPDATE        Enable weekly automatic updates"
    echo "2. 🛡️  REDUNDANT BACKUP   Both systemd service + cron (recommended)"
    echo "3. ⚙️  SYSTEMD ONLY       Just systemd service (clean)"
    echo "4. 📅 CRON ONLY          Just cron job (simple)"
    echo "5. 🎯 PROVIDER CONFIG    Configure DNS provider now"
    echo "6. 🌐 NETWORK DISCOVERY  Join peer swarm with auto-healing (NEW!)"
    echo "7. ✅ SKIP EXTRAS        Just install basic Access"
    echo ""
    printf "Select options (1,2,3,4,5,6,7) [default: 2,1]: "
    
    read -r SETUP_CHOICES
    SETUP_CHOICES="${SETUP_CHOICES:-2,1}"  # Default: redundant backup + auto-update
    
    # Parse choices
    echo "$SETUP_CHOICES" | grep -q "1" && {
        log "✓ Enabling auto-update (weekly)"
        USE_AUTO_UPDATE=true
    }
    
    echo "$SETUP_CHOICES" | grep -q "2" && {
        log "✓ Enabling redundant backup (service + cron)"
        USE_SYSTEMD=true
        USE_CRON=true
    }
    
    echo "$SETUP_CHOICES" | grep -q "3" && {
        log "✓ Enabling systemd service only"
        USE_SYSTEMD=true
        USE_CRON=false
    }
    
    echo "$SETUP_CHOICES" | grep -q "4" && {
        log "✓ Enabling cron job only"
        USE_SYSTEMD=false
        USE_CRON=true
    }
    
    echo "$SETUP_CHOICES" | grep -q "5" && {
        log "✓ Will configure DNS provider after installation"
        INTERACTIVE_MODE=true
    }
    
    echo "$SETUP_CHOICES" | grep -q "6" && {
        log "✓ Will setup network discovery and peer swarm"
        USE_NETWORK_DISCOVERY=true
    }
    
    echo "$SETUP_CHOICES" | grep -q "7" && {
        log "✓ Installing basic Access only"
        USE_AUTO_UPDATE=false
        USE_SYSTEMD=false
        USE_CRON=false
    }
    
    echo ""
    
    # Show what will be installed
    echo "📋 INSTALLATION SUMMARY:"
    echo "========================"
    [ "$USE_AUTO_UPDATE" = true ] && echo "  ✅ Auto-update: Weekly updates from GitHub"
    [ "$USE_SYSTEMD" = true ] && echo "  ✅ Systemd service: Background daemon every 5 minutes"
    [ "$USE_CRON" = true ] && echo "  ✅ Cron backup: Redundant cron job every 5 minutes"
    [ "$INTERACTIVE_MODE" = true ] && echo "  ✅ Provider setup: Interactive configuration after install"
    [ "$USE_NETWORK_DISCOVERY" = true ] && echo "  ✅ Network discovery: Auto-join peer swarm with self-healing"
    echo "  ✅ Clean clone: ~/access (for self-updates)"
    echo "  ✅ XDG compliance: ~/.config/access + ~/.local/share/access"
    echo ""
    
    printf "Proceed with installation? [Y/n]: "
    read -r CONFIRM_INSTALL
    if [ "$CONFIRM_INSTALL" = "n" ] || [ "$CONFIRM_INSTALL" = "N" ]; then
        log "Installation cancelled by user"
        exit 0
    fi
    
    echo ""
}

# Interactive Azure setup
interactive_azure() {
    echo ""
    log "📝 Azure DNS Configuration"
    echo "---------------------------"
    
    printf "Subscription ID: "
    read -r PROVIDER_SUBSCRIPTION_ID
    printf "Resource Group: "
    read -r PROVIDER_RESOURCE_GROUP
    printf "Tenant ID: "
    read -r PROVIDER_TENANT_ID
    printf "Client ID: "
    read -r PROVIDER_CLIENT_ID
    printf "Client Secret: "
    read -r PROVIDER_CLIENT_SECRET
    printf "Domain (e.g., example.com): "
    read -r PROVIDER_DOMAIN
    printf "Host record [@ for root domain]: "
    read -r PROVIDER_HOST
    PROVIDER_HOST="${PROVIDER_HOST:-@}"
    
    if [ -n "$PROVIDER_SUBSCRIPTION_ID" ] && [ -n "$PROVIDER_RESOURCE_GROUP" ] && \
       [ -n "$PROVIDER_TENANT_ID" ] && [ -n "$PROVIDER_CLIENT_ID" ] && \
       [ -n "$PROVIDER_CLIENT_SECRET" ] && [ -n "$PROVIDER_DOMAIN" ]; then
        "$INSTALL_DIR/$SCRIPT_NAME" config azure \
            --subscription-id="$PROVIDER_SUBSCRIPTION_ID" \
            --resource-group="$PROVIDER_RESOURCE_GROUP" \
            --tenant-id="$PROVIDER_TENANT_ID" \
            --client-id="$PROVIDER_CLIENT_ID" \
            --client-secret="$PROVIDER_CLIENT_SECRET" \
            --domain="$PROVIDER_DOMAIN" \
            --host="$PROVIDER_HOST"
        log "✓ Azure DNS configured successfully"
    else
        warn "Missing required fields, skipping configuration"
    fi
}

# Interactive Google Cloud setup
interactive_gcloud() {
    echo ""
    log "📝 Google Cloud DNS Configuration"
    echo "----------------------------------"
    
    printf "Project ID: "
    read -r PROVIDER_PROJECT_ID
    printf "Zone Name: "
    read -r PROVIDER_ZONE_NAME
    printf "Service Account Key (base64): "
    read -r PROVIDER_SERVICE_ACCOUNT_KEY
    printf "Domain (e.g., example.com): "
    read -r PROVIDER_DOMAIN
    printf "Host record [@ for root domain]: "
    read -r PROVIDER_HOST
    PROVIDER_HOST="${PROVIDER_HOST:-@}"
    
    if [ -n "$PROVIDER_PROJECT_ID" ] && [ -n "$PROVIDER_ZONE_NAME" ] && \
       [ -n "$PROVIDER_SERVICE_ACCOUNT_KEY" ] && [ -n "$PROVIDER_DOMAIN" ]; then
        "$INSTALL_DIR/$SCRIPT_NAME" config gcloud \
            --project-id="$PROVIDER_PROJECT_ID" \
            --zone-name="$PROVIDER_ZONE_NAME" \
            --service-account-key="$PROVIDER_SERVICE_ACCOUNT_KEY" \
            --domain="$PROVIDER_DOMAIN" \
            --host="$PROVIDER_HOST"
        log "✓ Google Cloud DNS configured successfully"
    else
        warn "Missing required fields, skipping configuration"
    fi
}

# Interactive Route53 setup
interactive_route53() {
    echo ""
    log "📝 AWS Route53 Configuration"
    echo "-----------------------------"
    
    printf "Hosted Zone ID: "
    read -r PROVIDER_ZONE_ID
    printf "Access Key ID: "
    read -r PROVIDER_ACCESS_KEY
    printf "Secret Access Key: "
    read -r PROVIDER_SECRET_KEY
    printf "Domain (e.g., example.com): "
    read -r PROVIDER_DOMAIN
    printf "Host record [@ for root domain]: "
    read -r PROVIDER_HOST
    PROVIDER_HOST="${PROVIDER_HOST:-@}"
    
    if [ -n "$PROVIDER_ZONE_ID" ] && [ -n "$PROVIDER_ACCESS_KEY" ] && \
       [ -n "$PROVIDER_SECRET_KEY" ] && [ -n "$PROVIDER_DOMAIN" ]; then
        "$INSTALL_DIR/$SCRIPT_NAME" config route53 \
            --zone-id="$PROVIDER_ZONE_ID" \
            --access-key="$PROVIDER_ACCESS_KEY" \
            --secret-key="$PROVIDER_SECRET_KEY" \
            --domain="$PROVIDER_DOMAIN" \
            --host="$PROVIDER_HOST"
        log "✓ AWS Route53 configured successfully"
    else
        warn "Missing required fields, skipping configuration"
    fi
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

File Locations (XDG Base Directory Specification):
=================================================
   Config:        ~/.config/access/config.json
   Data & Logs:   ~/.local/share/access/
   Update Log:    ~/.config/access/auto-update.log
   Clean Clone:   ~/access/ (used for self-updates)

EOF
}

# Parse arguments
parse_args() {
    USE_SYSTEMD=false
    USE_CRON=false
    USE_AUTO_UPDATE=false
    USE_NETWORK_DISCOVERY=false
    CRON_INTERVAL=5
    SHOW_HELP=false
    INTERACTIVE_MODE=false
    AUTO_DETECT_AUTOMATION=false
    
    # Discovery configuration
    DISCOVERY_DOMAIN=""
    DISCOVERY_PREFIX=""
    
    # Provider configuration flags
    PROVIDER=""
    PROVIDER_KEY=""
    PROVIDER_SECRET=""
    PROVIDER_EMAIL=""
    PROVIDER_TOKEN=""
    PROVIDER_DOMAIN=""
    PROVIDER_HOST="@"
    PROVIDER_ZONE_ID=""
    PROVIDER_SUBSCRIPTION_ID=""
    PROVIDER_RESOURCE_GROUP=""
    PROVIDER_TENANT_ID=""
    PROVIDER_CLIENT_ID=""
    PROVIDER_CLIENT_SECRET=""
    PROVIDER_PROJECT_ID=""
    PROVIDER_ZONE_NAME=""
    PROVIDER_SERVICE_ACCOUNT_KEY=""
    PROVIDER_ACCESS_KEY=""
    PROVIDER_SECRET_KEY=""
    
    # If no args, enable interactive mode BUT let redundant automation logic decide
    if [ $# -eq 0 ]; then
        INTERACTIVE_MODE=true
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
            --skip-interactive)
                SKIP_INTERACTIVE=true
                ;;
            --help|-h)
                SHOW_HELP=true
                ;;
            # Provider configuration flags
            --provider=*)
                PROVIDER="${arg#*=}"
                ;;
            --key=*)
                PROVIDER_KEY="${arg#*=}"
                ;;
            --secret=*)
                PROVIDER_SECRET="${arg#*=}"
                ;;
            --email=*)
                PROVIDER_EMAIL="${arg#*=}"
                ;;
            --token=*)
                PROVIDER_TOKEN="${arg#*=}"
                ;;
            --domain=*)
                PROVIDER_DOMAIN="${arg#*=}"
                ;;
            --host=*)
                PROVIDER_HOST="${arg#*=}"
                ;;
            --zone-id=*)
                PROVIDER_ZONE_ID="${arg#*=}"
                ;;
            --subscription-id=*)
                PROVIDER_SUBSCRIPTION_ID="${arg#*=}"
                ;;
            --resource-group=*)
                PROVIDER_RESOURCE_GROUP="${arg#*=}"
                ;;
            --tenant-id=*)
                PROVIDER_TENANT_ID="${arg#*=}"
                ;;
            --client-id=*)
                PROVIDER_CLIENT_ID="${arg#*=}"
                ;;
            --client-secret=*)
                PROVIDER_CLIENT_SECRET="${arg#*=}"
                ;;
            --project-id=*)
                PROVIDER_PROJECT_ID="${arg#*=}"
                ;;
            --zone-name=*)
                PROVIDER_ZONE_NAME="${arg#*=}"
                ;;
            --service-account-key=*)
                PROVIDER_SERVICE_ACCOUNT_KEY="${arg#*=}"
                ;;
            --access-key=*)
                PROVIDER_ACCESS_KEY="${arg#*=}"
                ;;
            --secret-key=*)
                PROVIDER_SECRET_KEY="${arg#*=}"
                ;;
            --interactive)
                INTERACTIVE_MODE=true
                ;;
            --network-discovery)
                USE_NETWORK_DISCOVERY=true
                ;;
            --discovery-domain=*)
                DISCOVERY_DOMAIN="${arg#*=}"
                USE_NETWORK_DISCOVERY=true
                ;;
            --discovery-prefix=*)
                DISCOVERY_PREFIX="${arg#*=}"
                USE_NETWORK_DISCOVERY=true
                ;;
            --prefix=*)
                INSTALL_DIR="${arg#*=}/bin"
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

  --systemd        Install systemd service only
  --service        Alias for --systemd
  --cron           Install cron job only  
  --interval=N     Set cron interval in minutes (default: 5)
  
  Default: Both systemd service AND cron backup (redundant automation)
  --auto-update         Enable weekly auto-updates
  --interactive         Force interactive mode
  --network-discovery   Enable peer swarm with auto-discovery
  --discovery-domain=D  Set discovery domain (default: akao.io)
  --discovery-prefix=P  Set host prefix (default: peer)
  --prefix=PATH         Installation prefix (default: /usr/local)
  --help                Show this help

Provider Configuration (CLI):
============================

  --provider=NAME  DNS provider (godaddy|cloudflare|digitalocean|azure|gcloud|route53)
  --domain=DOMAIN  Domain to manage
  --host=HOST      Host record (default: @)
  
  # GoDaddy
  --key=KEY --secret=SECRET
  
  # Cloudflare  
  --email=EMAIL --key=API_KEY --zone-id=ZONE_ID
  
  # DigitalOcean
  --token=API_TOKEN
  
  # Azure DNS
  --subscription-id=ID --resource-group=GROUP --tenant-id=ID --client-id=ID --client-secret=SECRET
  
  # Google Cloud DNS
  --project-id=ID --zone-name=NAME --service-account-key=KEY
  
  # AWS Route53
  --zone-id=ID --access-key=KEY --secret-key=SECRET

Examples:
=========

  # Interactive installation (default)
  ./install.sh

  # One-command GoDaddy setup
  ./install.sh --provider=godaddy --key=YOUR_KEY --secret=YOUR_SECRET --domain=example.com --systemd

  # One-command Cloudflare setup
  ./install.sh --provider=cloudflare --email=you@email.com --key=API_KEY --zone-id=ZONE --domain=example.com --cron --auto-update

  # Installation only (no provider config)
  ./install.sh --systemd --cron --interval=3 --auto-update

  # Install with network discovery (interactive)
  ./install.sh --network-discovery

  # Non-interactive network discovery setup
  ACCESS_DNS_PROVIDER=godaddy ACCESS_DNS_KEY=YOUR_KEY ACCESS_DNS_SECRET=YOUR_SECRET ./install.sh --network-discovery --discovery-domain=akao.io

  # Install to custom location (for testing)
  ./install.sh --prefix=/tmp/test_install --systemd

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
    
    # REDUNDANT AUTOMATION: Always install both systemd AND cron for backup
    if [ "$USE_SYSTEMD" = false ] && [ "$USE_CRON" = false ]; then
        log "Setting up REDUNDANT automation (service + cron backup)..."
        
        # Enable both if available
        if command -v systemctl >/dev/null 2>&1; then
            log "Systemd available - enabling service..."
            USE_SYSTEMD=true
        fi
        
        if command -v crontab >/dev/null 2>&1; then
            log "Cron available - enabling cron backup..."
            USE_CRON=true
        fi
        
        if [ "$USE_SYSTEMD" = false ] && [ "$USE_CRON" = false ]; then
            warn "Neither systemd nor cron available - manual setup required"
        fi
    fi
    
    # Setup systemd if requested or auto-detected
    if [ "$USE_SYSTEMD" = true ]; then
        if setup_systemd; then
            # Auto-start the service after installation
            if sudo -n true 2>/dev/null; then
                sudo systemctl start access
                log "✓ Service started automatically"
            else
                systemctl --user start access
                log "✓ User service started automatically"
            fi
        else
            warn "Failed to setup systemd service"
        fi
        echo ""
    fi
    
    # Setup cron if requested or auto-detected
    if [ "$USE_CRON" = true ]; then
        setup_cron "$CRON_INTERVAL" || warn "Failed to setup cron job"
        echo ""
    fi
    
    # Setup auto-update if requested
    if [ "$USE_AUTO_UPDATE" = true ]; then
        setup_auto_update
        echo ""
    fi
    
    # Configure provider from CLI flags (if provided)
    configure_provider_from_flags
    
    # Always run enhanced setup menu unless explicitly skipped
    if [ "$SKIP_INTERACTIVE" != true ]; then
        enhanced_setup_menu
    fi
    
    # Legacy interactive setup for provider only
    if [ "$INTERACTIVE_MODE" = true ] && [ -z "$PROVIDER" ]; then
        interactive_setup
    fi
    
    # Setup network discovery if requested
    if [ "$USE_NETWORK_DISCOVERY" = true ]; then
        echo ""
        if [ -n "$PROVIDER" ] && [ -n "$PROVIDER_KEY" ]; then
            # Non-interactive discovery setup
            setup_network_discovery "non-interactive"
        else
            # Interactive discovery setup
            setup_network_discovery "interactive"
        fi
        echo ""
    fi
    
    # Show completion message
    log "Installation complete!"
    echo "=================================================="
    echo ""
    
    if [ "$USE_SYSTEMD" = true ] && [ "$USE_CRON" = true ]; then
        log "🔄 REDUNDANT AUTOMATION ENABLED"
        log "  ✅ Systemd service running (primary)"
        log "  ✅ Cron backup every $CRON_INTERVAL minutes"  
        log "  🛡️  When service dies → cron works"
        log "  🛡️  When cron dies → service works"
        log "  🧠 Smart conflict avoidance (4-minute minimum interval)"
        echo ""
    fi
    
    # Test the installation
    echo ""
    log "🧪 Testing installation..."
    if "$INSTALL_DIR/$SCRIPT_NAME" ip >/dev/null 2>&1; then
        log "✓ Access installed and working correctly"
        echo ""
        log "Ready to use! Try:"
        log "  access ip         # Test IP detection"
        if [ -f "$HOME/.config/access/config.json" ]; then
            log "  access update     # Update your DNS"
        fi
    else
        warn "Installation completed but access command test failed"
        log "You may need to add $INSTALL_DIR to your PATH"
    fi
    
    # Show provider help only if no provider was configured
    if [ -z "$PROVIDER" ] && [ "$INTERACTIVE_MODE" = false ]; then
        show_provider_help
    fi
}

# Run main
main "$@"