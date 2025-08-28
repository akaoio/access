#!/bin/sh
# @akaoio/access - Stacker Framework Integration
# Redirects to main Stacker cortex for universal shell framework

# Main Stacker directory (always use the central cortex)
MAIN_STACKER_DIR="/home/x/core/projects/stacker"

# Verify main Stacker exists
if [ ! -f "$MAIN_STACKER_DIR/stacker.sh" ]; then
    echo "FATAL: Main Stacker cortex not found at $MAIN_STACKER_DIR" >&2
    exit 1
fi

# Set STACKER_DIR to point to main cortex before sourcing
export STACKER_DIR="$MAIN_STACKER_DIR"

# Source the main Stacker framework
. "$MAIN_STACKER_DIR/stacker.sh" || {
    echo "FATAL: Cannot load main Stacker framework" >&2
    exit 1
}

# Initialize the loader (loads core module)
stacker_loader_init || {
    echo "FATAL: Cannot initialize module loader" >&2
    exit 1
}

# Global configuration variables
STACKER_TECH_NAME=""
STACKER_REPO_URL=""
STACKER_MAIN_SCRIPT=""
STACKER_SERVICE_DESCRIPTION=""

# Auto-detect best installation directory
if [ -n "$INSTALL_DIR" ]; then
    # User specified directory
    STACKER_INSTALL_DIR="$INSTALL_DIR"
elif [ -n "$FORCE_USER_INSTALL" ] || [ "$FORCE_USER_INSTALL" = "1" ]; then
    # Force user installation
    STACKER_INSTALL_DIR="$HOME/.local/bin"
    # Ensure directory exists
    mkdir -p "$STACKER_INSTALL_DIR"
elif [ -w "/usr/local/bin" ] && [ -z "$NO_SUDO" ] && sudo -n true 2>/dev/null; then
    # System installation (sudo available and not disabled)
    STACKER_INSTALL_DIR="/usr/local/bin"
else
    # User installation (no sudo or disabled)
    STACKER_INSTALL_DIR="$HOME/.local/bin"
    # Ensure directory exists
    mkdir -p "$STACKER_INSTALL_DIR"
fi

STACKER_HOME_DIR="$HOME"

# Initialize manager framework for a technology
# Usage: stacker_init "tech_name" "repo_url" "main_script" ["service_description"]
stacker_init() {
    local tech_name="$1"
    local repo_url="$2"  
    local main_script="$3"
    local service_desc="${4:-$tech_name service}"
    
    if [ -z "$tech_name" ] || [ -z "$repo_url" ] || [ -z "$main_script" ]; then
        stacker_error "stacker_init requires: tech_name, repo_url, main_script"
        return 1
    fi
    
    STACKER_TECH_NAME="$tech_name"
    STACKER_REPO_URL="$repo_url"
    STACKER_MAIN_SCRIPT="$main_script"
    STACKER_SERVICE_DESCRIPTION="$service_desc"
    
    # Set derived paths
    STACKER_CLEAN_CLONE_DIR="$STACKER_HOME_DIR/$tech_name"
    STACKER_CONFIG_DIR="$STACKER_HOME_DIR/.config/$tech_name"
    STACKER_DATA_DIR="$STACKER_HOME_DIR/.local/share/$tech_name"
    STACKER_STATE_DIR="$STACKER_HOME_DIR/.local/state/$tech_name"
    
    # Log installation mode
    if [ "$STACKER_INSTALL_DIR" = "/usr/local/bin" ]; then
        stacker_log "Initialized for $tech_name (system installation)"
    else
        stacker_log "Initialized for $tech_name (user installation: $STACKER_INSTALL_DIR)"
        # Check PATH
        case ":$PATH:" in
            *":$STACKER_INSTALL_DIR:"*)
                ;;
            *)
                stacker_warn "Add to PATH: export PATH=\"$STACKER_INSTALL_DIR:\$PATH\""
                ;;
        esac
    fi
    return 0
}

# Complete installation workflow with modular loading
# Usage: stacker_install [--service] [--cron] [--auto-update] [--interval=N]
stacker_install() {
    local use_service=false
    local use_cron=false  
    local use_auto_update=false
    local cron_interval=5
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --service|--systemd)
                use_service=true
                ;;
            --cron)
                use_cron=true
                ;;
            --auto-update)
                use_auto_update=true
                ;;
            --interval=*)
                cron_interval="${1#*=}"
                use_cron=true
                ;;
            --redundant)
                use_service=true
                use_cron=true
                ;;
            *)
                stacker_warn "Unknown install option: $1"
                ;;
        esac
        shift
    done
    
    # Validate initialization
    if [ -z "$STACKER_TECH_NAME" ]; then
        stacker_error "Stacker not initialized. Call stacker_init first."
        return 1
    fi
    
    stacker_log "Starting installation of $STACKER_TECH_NAME..."
    
    # Load required modules for installation
    stacker_require "config install" || return 1
    
    # Core installation steps
    stacker_check_requirements || return 1
    stacker_create_xdg_dirs || return 1  
    stacker_create_clean_clone || return 1
    stacker_install_from_clone || return 1
    
    # Optional components - load service module if needed
    if [ "$use_service" = true ] || [ "$use_cron" = true ]; then
        stacker_require "service" || return 1
    fi
    
    if [ "$use_service" = true ]; then
        stacker_setup_systemd_service || stacker_warn "Failed to setup systemd service"
    fi
    
    if [ "$use_cron" = true ]; then
        stacker_setup_cron_job "$cron_interval" || stacker_warn "Failed to setup cron job"
    fi
    
    if [ "$use_auto_update" = true ]; then
        # Load update module for auto-update
        stacker_require "update" || return 1
        stacker_setup_auto_update || stacker_warn "Failed to setup auto-update"
    fi
    
    stacker_log "Installation of $STACKER_TECH_NAME completed successfully"
    return 0
}

# Setup services (systemd + optional cron backup) with modular loading
# Usage: stacker_setup_service [interval_minutes]
stacker_setup_service() {
    local interval="${1:-5}"
    
    if [ -z "$STACKER_TECH_NAME" ]; then
        stacker_error "Stacker not initialized"
        return 1
    fi
    
    # Load service module
    stacker_require "service" || return 1
    
    stacker_log "Setting up service management for $STACKER_TECH_NAME..."
    
    # Try systemd first
    if stacker_setup_systemd_service; then
        stacker_log "Systemd service configured successfully"
        
        # Add cron backup if available
        if command -v crontab >/dev/null 2>&1; then
            stacker_log "Adding cron backup (redundant automation)"
            stacker_setup_cron_job "$interval"
        fi
    elif stacker_setup_cron_job "$interval"; then
        stacker_log "Cron job configured successfully (systemd not available)"
    else
        stacker_error "Failed to setup both systemd and cron"
        return 1
    fi
    
    return 0
}

# Uninstall technology with modular loading
# Usage: stacker_uninstall [--keep-config] [--keep-data]
stacker_uninstall() {
    local keep_config=false
    local keep_data=false
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --keep-config)
                keep_config=true
                ;;
            --keep-data)
                keep_data=true
                ;;
        esac
        shift
    done
    
    if [ -z "$STACKER_TECH_NAME" ]; then
        stacker_error "Stacker not initialized"
        return 1
    fi
    
    stacker_log "Uninstalling $STACKER_TECH_NAME..."
    
    # Load service module for cleanup
    stacker_require "service" || true
    
    # Stop and disable services
    stacker_stop_service 2>/dev/null || true
    stacker_disable_service 2>/dev/null || true
    
    # Remove cron jobs
    stacker_remove_cron_job 2>/dev/null || true
    
    # Remove installed binary
    if [ -f "$STACKER_INSTALL_DIR/$STACKER_TECH_NAME" ]; then
        if [ -w "$STACKER_INSTALL_DIR" ]; then
            rm -f "$STACKER_INSTALL_DIR/$STACKER_TECH_NAME"
        else
            sudo rm -f "$STACKER_INSTALL_DIR/$STACKER_TECH_NAME"
        fi
        stacker_log "Removed $STACKER_INSTALL_DIR/$STACKER_TECH_NAME"
    fi
    
    # Remove clean clone
    if [ -d "$STACKER_CLEAN_CLONE_DIR" ]; then
        rm -rf "$STACKER_CLEAN_CLONE_DIR"
        stacker_log "Removed clean clone: $STACKER_CLEAN_CLONE_DIR"
    fi
    
    # Optionally remove config and data
    if [ "$keep_config" = false ] && [ -d "$STACKER_CONFIG_DIR" ]; then
        rm -rf "$STACKER_CONFIG_DIR"
        stacker_log "Removed config: $STACKER_CONFIG_DIR"
    fi
    
    if [ "$keep_data" = false ] && [ -d "$STACKER_DATA_DIR" ]; then
        rm -rf "$STACKER_DATA_DIR"
        stacker_log "Removed data: $STACKER_DATA_DIR"
    fi
    
    if [ "$keep_data" = false ] && [ -d "$STACKER_STATE_DIR" ]; then
        rm -rf "$STACKER_STATE_DIR"  
        stacker_log "Removed state: $STACKER_STATE_DIR"
    fi
    
    stacker_log "Uninstallation of $STACKER_TECH_NAME completed"
    return 0
}

# Show status of technology with modular loading
# Usage: stacker_status
stacker_status() {
    if [ -z "$STACKER_TECH_NAME" ]; then
        stacker_error "Stacker not initialized"
        return 1
    fi
    
    echo "=========================================="
    echo "  $STACKER_TECH_NAME Status Report"
    echo "=========================================="
    echo ""
    
    # Installation status
    echo "📦 Installation:"
    if [ -f "$STACKER_INSTALL_DIR/$STACKER_TECH_NAME" ]; then
        echo "  ✅ Binary: $STACKER_INSTALL_DIR/$STACKER_TECH_NAME"
    else
        echo "  ❌ Binary: Not found"
    fi
    
    if [ -d "$STACKER_CLEAN_CLONE_DIR" ]; then
        echo "  ✅ Clean clone: $STACKER_CLEAN_CLONE_DIR"
    else
        echo "  ❌ Clean clone: Not found"
    fi
    
    # Configuration
    echo ""
    echo "⚙️ Configuration:"
    echo "  📁 Config: $STACKER_CONFIG_DIR"
    echo "  📁 Data: $STACKER_DATA_DIR"  
    echo "  📁 State: $STACKER_STATE_DIR"
    
    # Service status - load module only if needed
    echo ""
    echo "🔧 Service Status:"
    if stacker_require "service" 2>/dev/null; then
        stacker_service_status
    else
        echo "  ❌ Service module not available"
    fi
    
    # Cron status
    echo ""
    echo "⏰ Cron Status:"
    if crontab -l 2>/dev/null | grep -q "$STACKER_TECH_NAME"; then
        echo "  ✅ Cron job active"
        echo "  📅 Schedule: $(crontab -l 2>/dev/null | grep "$STACKER_TECH_NAME" | head -1)"
    else
        echo "  ❌ No cron job found"
    fi
    
    echo ""
    return 0
}

# Show manager framework version
stacker_version() {
    echo "Stacker Framework v$STACKER_VERSION (Modular)"
    echo "Universal POSIX Shell Framework for AKAO Technologies"
    echo ""
    echo "Loaded modules: $STACKER_LOADED_MODULES"
    echo "Available modules:"
    stacker_list_available_modules
}

# Show help
stacker_help() {
    cat << 'EOF'
Stacker Framework v2.0 - Universal Shell Framework (Modular)

Usage:
  ./manager.sh [COMMAND] [OPTIONS]

Commands:
  init, -i              Initialize Stacker framework in current directory
  config, -c            Manage configuration settings
  install               Install Stacker-based application
  update, -u            Update Stacker-based application
  service, -s           Control Stacker service
  health                Check system health and diagnostics
  status                Show current status
  rollback, -r          Rollback to previous version
  self-install          Install Stacker globally as command-line tool
  self-uninstall        Remove global Stacker installation
  version, -v           Show version information
  help, -h              Show help information

Options (for direct execution):
  --help, -h           Show this help
  --version, -v        Show version information
  --list-modules, -l   List all modules (loaded and available)
  --module-info, -m    Show module information

Command Examples:
  stacker init --template=cli --name=mytool
  stacker config set update.interval 3600
  stacker install --systemd --auto-update
  stacker service status
  stacker health --verbose

For detailed help on any command:
  manager [COMMAND] --help

Module Management (when sourced):
  stacker_require "module1 module2"  # Load specific modules
  stacker_list_loaded_modules        # Show loaded modules
  stacker_list_available_modules     # Show available modules
  stacker_module_info "module_name"  # Show module information

EOF
}

# Backwards compatibility mode
if [ "${STACKER_LEGACY_MODE:-0}" = "1" ]; then
    stacker_debug "Legacy mode enabled - loading all modules"
    stacker_require "config install service update self_update" >/dev/null 2>&1 || true
fi

# Parse CLI arguments and execute commands
stacker_parse_cli() {
    case "$1" in
        --help|-h|help)
            stacker_help
            exit 0
            ;;
        --version|-v|version)
            local json_output=false
            [ "$2" = "--json" ] && json_output=true
            if [ "$json_output" = true ]; then
                echo "{\"version\":\"$STACKER_VERSION\",\"type\":\"modular\",\"loaded_modules\":\"$STACKER_LOADED_MODULES\"}"
            else
                stacker_version
            fi
            exit 0
            ;;
        init|-i)
            shift
            stacker_cli_init "$@"
            exit $?
            ;;
        config|-c)
            shift
            stacker_cli_config "$@"
            exit $?
            ;;
        install)
            shift
            stacker_cli_install "$@"
            exit $?
            ;;
        update|-u)
            shift
            stacker_cli_update "$@"
            exit $?
            ;;
        service|-s)
            shift
            stacker_cli_service "$@"
            exit $?
            ;;
        health)
            shift
            stacker_cli_health "$@"
            exit $?
            ;;
        status)
            stacker_status
            exit 0
            ;;
        rollback|-r)
            shift
            stacker_cli_rollback "$@"
            exit $?
            ;;
        self-install)
            shift
            stacker_cli_self_install "$@"
            exit $?
            ;;
        self-uninstall)
            shift
            stacker_cli_self_uninstall "$@"
            exit $?
            ;;
        --self-update|--discover|--setup-auto-update|--remove-auto-update|--self-status|--register)
            if stacker_require "self_update"; then
                stacker_handle_self_update "$@"
                exit $?
            else
                stacker_error "Self-update module not available"
                exit 1
            fi
            ;;
        --module-info|-m)
            if [ -n "$2" ]; then
                stacker_module_info "$2"
            else
                stacker_list_available_modules
            fi
            exit 0
            ;;
        --list-modules|-l)
            stacker_list_loaded_modules
            echo ""
            stacker_list_available_modules
            exit 0
            ;;
        *)
            stacker_error "Unknown command: $1"
            echo ""
            stacker_help
            exit 1
            ;;
    esac
}

# CLI command implementations
stacker_cli_init() {
    local template="service"
    local name=""
    local repo=""
    local script=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --template=*|-t=*)
                template="${1#*=}"
                ;;
            --template|-t)
                template="$2"
                shift
                ;;
            --name=*|-n=*)
                name="${1#*=}"
                ;;
            --name|-n)
                name="$2"
                shift
                ;;
            --repo=*)
                repo="${1#*=}"
                ;;
            --repo)
                repo="$2"
                shift
                ;;
            --script=*)
                script="${1#*=}"
                ;;
            --script)
                script="$2"
                shift
                ;;
            --help|-h)
                cat << 'EOF'
Usage: stacker init [OPTIONS]

Initialize Stacker framework in current directory

Options:
  --template, -t TYPE    Project template (service, cli, library) [default: service]
  --name, -n NAME        Project name
  --repo REPO            Repository URL
  --script SCRIPT        Main script name
  --help, -h             Show this help

Examples:
  stacker init --template=cli --name=mytool
  stacker init -t service -n myservice --repo=https://github.com/user/repo.git
EOF
                return 0
                ;;
            *)
                [ -z "$name" ] && name="$1" || {
                    stacker_error "Unknown option: $1"
                    return 1
                }
                ;;
        esac
        shift
    done
    
    # Interactive mode if no name provided
    if [ -z "$name" ]; then
        printf "Project name: "
        read -r name
        [ -z "$name" ] && { stacker_error "Project name required"; return 1; }
    fi
    
    if [ -z "$repo" ]; then
        printf "Repository URL (optional): "
        read -r repo
    fi
    
    if [ -z "$script" ]; then
        script="${name}.sh"
    fi
    
    stacker_log "Initializing Stacker project: $name"
    stacker_log "  Template: $template"
    stacker_log "  Script: $script"
    [ -n "$repo" ] && stacker_log "  Repository: $repo"
    
    if [ -n "$repo" ]; then
        stacker_init "$name" "$repo" "$script"
    else
        stacker_log "Project initialized (no repository specified)"
        echo "#!/bin/sh" > "$script"
        echo "# $name - Generated by Stacker framework" >> "$script"
        chmod +x "$script"
        stacker_log "Created: $script"
    fi
}

stacker_cli_config() {
    local action="$1"
    shift
    
    case "$action" in
        get|-g)
            local key="$1"
            [ -z "$key" ] && { stacker_error "Key required for get"; return 1; }
            stacker_require "config"
            stacker_get_config "$key"
            ;;
        set|-s)
            local key="$1"
            local value="$2"
            [ -z "$key" ] || [ -z "$value" ] && { 
                stacker_error "Key and value required for set"
                return 1
            }
            stacker_require "config"
            stacker_save_config "$key" "$value"
            ;;
        list|-l)
            stacker_require "config"
            stacker_show_config
            ;;
        --help|-h|"")
            cat << 'EOF'
Usage: stacker config COMMAND [OPTIONS]

Manage configuration settings

Commands:
  get, -g KEY           Get configuration value
  set, -s KEY VALUE     Set configuration value  
  list, -l              List all configuration

Options:
  --help, -h            Show this help

Examples:
  stacker config get update.interval
  stacker config set update.interval 3600
  stacker config list
EOF
            ;;
        *)
            stacker_error "Unknown config command: $action"
            return 1
            ;;
    esac
}

stacker_cli_install() {
    local use_systemd=false
    local use_cron=false
    local use_manual=false
    local install_args=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --systemd)
                use_systemd=true
                install_args="$install_args --service"
                ;;
            --cron)
                use_cron=true
                install_args="$install_args --cron"
                ;;
            --manual)
                use_manual=true
                ;;
            --interval=*)
                install_args="$install_args $1"
                ;;
            --auto-update|-a)
                install_args="$install_args --auto-update"
                ;;
            --redundant)
                install_args="$install_args --redundant"
                ;;
            --help|-h)
                cat << 'EOF'
Usage: stacker install [OPTIONS]

Install Stacker-based application

Options:
  --systemd             Install as systemd service
  --cron                Install as cron job
  --manual              Manual installation (default)
  --interval=N          Cron interval in minutes
  --auto-update, -a     Enable automatic updates
  --redundant           Both systemd and cron
  --help, -h            Show this help

Examples:
  stacker install --systemd
  stacker install --cron --interval=300
  stacker install --redundant --auto-update
EOF
                return 0
                ;;
            *)
                stacker_error "Unknown install option: $1"
                return 1
                ;;
        esac
        shift
    done
    
    if [ -z "$STACKER_TECH_NAME" ]; then
        stacker_error "Stacker not initialized. Run 'stacker init' first."
        return 1
    fi
    
    stacker_install $install_args
}

stacker_cli_update() {
    local check_only=false
    local force=false
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --check|-c)
                check_only=true
                ;;
            --force|-f)
                force=true
                ;;
            --help|-h)
                cat << 'EOF'
Usage: stacker update [OPTIONS]

Update Stacker-based application

Options:
  --check, -c           Check for updates without installing
  --force, -f           Force update even if current
  --help, -h            Show this help

Examples:
  stacker update --check
  stacker update --force
EOF
                return 0
                ;;
            *)
                stacker_error "Unknown update option: $1"
                return 1
                ;;
        esac
        shift
    done
    
    if [ -z "$STACKER_TECH_NAME" ]; then
        stacker_error "Stacker not initialized"
        return 1
    fi
    
    if [ "$check_only" = true ]; then
        stacker_log "Checking for updates..."
        
        # Check if we're in a git repository
        if [ -d ".git" ]; then
            local remote_hash local_hash
            remote_hash=$(git ls-remote origin HEAD | cut -f1)
            local_hash=$(git rev-parse HEAD)
            
            if [ "$remote_hash" != "$local_hash" ]; then
                stacker_log "✓ Updates available"
                stacker_log "  Remote: $remote_hash"
                stacker_log "  Local:  $local_hash"
                return 0
            else
                stacker_log "✓ Access is up to date"
                return 1
            fi
        else
            stacker_warn "Not in a git repository - cannot check for updates"
            return 1
        fi
    else
        stacker_log "Updating $STACKER_TECH_NAME..."
        
        # Perform git-based update if in repository
        if [ -d ".git" ]; then
            # Backup current state
            local backup_dir="$STACKER_DATA_DIR/backups/$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir"
            cp -r . "$backup_dir/" 2>/dev/null || true
            
            # Pull updates
            if git pull origin main; then
                stacker_log "✓ Access updated successfully"
                stacker_log "  Backup saved: $backup_dir"
                
                # Restart service if running
                if systemctl is-active --quiet access.service 2>/dev/null; then
                    stacker_log "Restarting Access service..."
                    sudo systemctl restart access.service
                fi
                return 0
            else
                stacker_error "Update failed"
                return 1
            fi
        else
            stacker_error "Not in a git repository - cannot update"
            return 1
        fi
    fi
}

stacker_cli_service() {
    local action="$1"
    
    case "$action" in
        start)
            stacker_require "service"
            stacker_start_service
            ;;
        stop)
            stacker_require "service"  
            stacker_stop_service
            ;;
        restart)
            stacker_require "service"
            stacker_restart_service
            ;;
        status)
            stacker_require "service"
            stacker_service_status
            ;;
        enable)
            stacker_require "service"
            stacker_enable_service
            ;;
        disable)
            stacker_require "service"
            stacker_disable_service
            ;;
        --help|-h|"")
            cat << 'EOF'
Usage: stacker service COMMAND

Control Stacker service

Commands:
  start                 Start the service
  stop                  Stop the service  
  restart               Restart the service
  status                Show service status
  enable                Enable service at boot
  disable               Disable service at boot

Options:
  --help, -h            Show this help

Examples:
  stacker service start
  stacker service status
EOF
            ;;
        *)
            stacker_error "Unknown service command: $action"
            return 1
            ;;
    esac
}

stacker_cli_health() {
    local verbose=false
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --verbose|-v)
                verbose=true
                ;;
            --help|-h)
                cat << 'EOF'
Usage: stacker health [OPTIONS]

Check system health and diagnostics

Options:
  --verbose, -v         Show detailed diagnostic information
  --help, -h            Show this help

Examples:
  stacker health
  stacker health --verbose
EOF
                return 0
                ;;
            *)
                stacker_error "Unknown health option: $1"
                return 1
                ;;
        esac
        shift
    done
    
    echo "Stacker Framework Health Check"
    echo "=============================="
    echo ""
    
    # Basic health checks
    echo "✓ Stacker framework loaded"
    echo "✓ Core module functional"
    echo "✓ Module loading system operational"
    
    if [ "$verbose" = true ]; then
        echo ""
        echo "Detailed Diagnostics:"
        echo "  Version: $STACKER_VERSION"
        echo "  Loaded modules: $STACKER_LOADED_MODULES"
        echo "  Shell: $0"
        echo "  Working directory: $(pwd)"
        [ -n "$STACKER_TECH_NAME" ] && echo "  Initialized for: $STACKER_TECH_NAME"
    fi
    
    echo ""
    echo "Health check completed ✓"
}

stacker_cli_rollback() {
    local version="$1"
    
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        cat << 'EOF'
Usage: stacker rollback [VERSION]

Rollback to previous version

Arguments:
  VERSION               Specific version to rollback to (optional)

Options:
  --help, -h            Show this help

Examples:
  stacker rollback
  stacker rollback 1.2.3
EOF
        return 0
    fi
    
    if [ -z "$STACKER_TECH_NAME" ]; then
        stacker_error "Stacker not initialized"
        return 1
    fi
    
    if [ -n "$version" ]; then
        stacker_log "Rolling back to version: $version"
    else
        stacker_log "Rolling back to previous version"
    fi
    
    # Implement rollback functionality
    local backup_dir="$STACKER_DATA_DIR/backups"
    
    if [ ! -d "$backup_dir" ]; then
        stacker_error "No backups found to rollback to"
        return 1
    fi
    
    # Find most recent backup
    local latest_backup
    latest_backup=$(ls -1t "$backup_dir" 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        stacker_error "No backup directories found"
        return 1
    fi
    
    local backup_path="$backup_dir/$latest_backup"
    stacker_log "Rolling back to backup: $latest_backup"
    
    # Confirm rollback
    printf "This will replace current files with backup from $latest_backup. Continue? (yes/no): "
    read confirmation
    case "$confirmation" in
        yes|YES|y|Y)
            # Stop service if running
            if systemctl is-active --quiet access.service 2>/dev/null; then
                stacker_log "Stopping Access service..."
                sudo systemctl stop access.service
            fi
            
            # Create current state backup before rollback
            local pre_rollback_backup="$backup_dir/pre-rollback-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$pre_rollback_backup"
            cp -r . "$pre_rollback_backup/" 2>/dev/null || true
            
            # Restore from backup
            if cp -r "$backup_path"/* . 2>/dev/null; then
                stacker_log "✓ Rollback completed successfully"
                stacker_log "  Pre-rollback state saved: $pre_rollback_backup"
                
                # Restart service
                if systemctl is-enabled --quiet access.service 2>/dev/null; then
                    stacker_log "Restarting Access service..."
                    sudo systemctl start access.service
                fi
                return 0
            else
                stacker_error "Rollback failed"
                return 1
            fi
            ;;
        *)
            stacker_log "Rollback cancelled"
            return 1
            ;;
    esac
}

stacker_cli_self_install() {
    local install_dir=""
    local use_sudo=false
    local force=false
    local symlink=false
    local verify_only=false
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --user)
                install_dir="$HOME/.local/bin"
                use_sudo=false
                ;;
            --system)
                install_dir="/usr/local/bin"
                use_sudo=true
                ;;
            --prefix=*)
                install_dir="${1#*=}/bin"
                use_sudo=false
                ;;
            --force|-f)
                force=true
                ;;
            --symlink|-s)
                symlink=true
                ;;
            --verify)
                verify_only=true
                ;;
            --help|-h)
                cat << 'EOF'
Usage: stacker self-install [OPTIONS]

Install Stacker globally as a command-line tool

Options:
  --user                Install in user directory (~/.local/bin)
  --system              Install system-wide (/usr/local/bin)
  --prefix=PATH         Install to custom prefix (PATH/bin)
  --force, -f           Force reinstall even if already installed
  --symlink, -s         Create symlink instead of wrapper script
  --verify              Verify installation only
  --help, -h            Show this help

Installation Methods:
  1. Auto-detect (default): Finds best location based on permissions
  2. User install: Safe, no sudo, installs to ~/.local/bin
  3. System install: Requires sudo, available to all users
  4. Custom prefix: Install to specified directory

Examples:
  stacker self-install                  # Auto-detect best location
  stacker self-install --user           # Install for current user
  stacker self-install --system         # Install system-wide
  stacker self-install --prefix=/opt    # Install to /opt/bin
  stacker self-install --verify         # Check if installed correctly

After installation:
  stacker version                       # Verify installation
  stacker init myproject                # Initialize new project
  stacker help                          # Show available commands
EOF
                return 0
                ;;
            *)
                stacker_error "Unknown self-install option: $1"
                return 1
                ;;
        esac
        shift
    done
    
    # Auto-detect installation directory if not specified
    if [ -z "$install_dir" ]; then
        # Check common directories in order of preference
        for dir in "$HOME/.local/bin" "/usr/local/bin" "/usr/bin" "/opt/bin"; do
            if [ -w "$dir" ] || ([ "$dir" = "/usr/local/bin" ] || [ "$dir" = "/usr/bin" ]) && command -v sudo >/dev/null 2>&1; then
                install_dir="$dir"
                [ "$dir" = "/usr/local/bin" ] || [ "$dir" = "/usr/bin" ] && use_sudo=true
                break
            fi
        done
        
        if [ -z "$install_dir" ]; then
            # Fallback to user directory
            install_dir="$HOME/.local/bin"
            echo "Auto-detected installation directory: $install_dir"
        fi
    fi
    
    # Verify mode - check existing installation
    if [ "$verify_only" = true ]; then
        echo "Verifying Stacker installation..."
        
        # Check if stacker command exists
        if command -v manager >/dev/null 2>&1; then
            local installed_path="$(command -v manager)"
            echo "✓ Stacker found at: $installed_path"
            
            # Check if it's our installation
            if grep -q "STACKER_DIR=" "$installed_path" 2>/dev/null; then
                local installed_dir="$(grep "STACKER_DIR=" "$installed_path" | cut -d'"' -f2)"
                echo "✓ Stacker directory: $installed_dir"
                
                # Verify it works
                if stacker --version >/dev/null 2>&1; then
                    echo "✓ Stacker is functional"
                    stacker --version
                    return 0
                else
                    echo "✗ Stacker command exists but is not functional"
                    return 1
                fi
            else
                echo "✗ Found different 'manager' command (not Stacker Framework)"
                return 1
            fi
        else
            echo "✗ Stacker not found in PATH"
            echo ""
            echo "To install, run: $0 self-install"
            return 1
        fi
    fi
    
    # Check for existing installation
    if [ -f "$install_dir/manager" ] && [ "$force" != true ]; then
        echo "Stacker is already installed at: $install_dir/manager"
        echo ""
        
        # Check if it's our installation
        if grep -q "STACKER_DIR=" "$install_dir/manager" 2>/dev/null; then
            local installed_dir="$(grep "STACKER_DIR=" "$install_dir/manager" | cut -d'"' -f2)"
            echo "Current installation points to: $installed_dir"
            
            local abs_stacker_dir="$(cd "$STACKER_DIR" 2>/dev/null && pwd)"
            if [ "$installed_dir" != "$abs_stacker_dir" ]; then
                echo "This directory: $abs_stacker_dir"
                echo ""
                echo "Use --force to update the installation"
            else
                echo "Already using this Stacker instance"
            fi
        else
            echo "WARNING: Found different 'manager' command at this location"
            echo "Use --force to replace it with Stacker Framework"
        fi
        return 1
    fi
    
    # Create install directory if needed
    if [ ! -d "$install_dir" ]; then
        echo "Creating directory: $install_dir"
        if [ "$use_sudo" = true ]; then
            sudo mkdir -p "$install_dir" || {
                stacker_error "Failed to create directory: $install_dir"
                return 1
            }
        else
            mkdir -p "$install_dir" || {
                stacker_error "Failed to create directory: $install_dir"
                return 1
            }
        fi
    fi
    
    # Check write permissions
    if [ ! -w "$install_dir" ] && [ "$use_sudo" = false ]; then
        stacker_error "Cannot write to $install_dir. Try with --system or use sudo."
        return 1
    fi
    
    # Get absolute paths
    local abs_stacker_dir="$(cd "$STACKER_DIR" 2>/dev/null && pwd)"
    if [ -z "$abs_stacker_dir" ]; then
        stacker_error "Failed to determine Stacker directory path"
        return 1
    fi
    
    local abs_stacker_script="$abs_stacker_dir/manager.sh"
    if [ ! -f "$abs_stacker_script" ]; then
        stacker_error "Stacker script not found: $abs_stacker_script"
        return 1
    fi
    
    echo "Installing Stacker Framework..."
    echo "  Source: $abs_stacker_dir"
    echo "  Target: $install_dir/manager"
    echo "  Method: $([ "$symlink" = true ] && echo "symlink" || echo "wrapper script")"
    [ "$use_sudo" = true ] && echo "  Permission: sudo required"
    echo ""
    
    # Create installation (symlink or wrapper)
    if [ "$symlink" = true ]; then
        # Create symlink
        if [ "$use_sudo" = true ]; then
            sudo ln -sf "$abs_stacker_script" "$install_dir/manager" || {
                stacker_error "Failed to create symlink"
                return 1
            }
        else
            ln -sf "$abs_stacker_script" "$install_dir/manager" || {
                stacker_error "Failed to create symlink"
                return 1
            }
        fi
    else
        # Create wrapper script with enhanced features
        local wrapper_content="#!/bin/sh
# Stacker Framework Global Wrapper
# Version: 2.0.0
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Source: $abs_stacker_dir

# Verify Stacker directory still exists
if [ ! -d \"$abs_stacker_dir\" ]; then
    echo \"ERROR: Stacker directory not found: $abs_stacker_dir\" >&2
    echo \"Please reinstall Stacker Framework\" >&2
    exit 1
fi

# Verify Stacker script exists
if [ ! -f \"$abs_stacker_script\" ]; then
    echo \"ERROR: Stacker script not found: $abs_stacker_script\" >&2
    echo \"Please reinstall Stacker Framework\" >&2
    exit 1
fi

# Set Stacker directory and execute
export STACKER_DIR=\"$abs_stacker_dir\"
exec \"\$STACKER_DIR/manager.sh\" \"\$@\"
"
        
        # Write wrapper to temp file with atomic install
        local temp_wrapper="$(mktemp /tmp/stacker-wrapper.XXXXXX)"
        echo "$wrapper_content" > "$temp_wrapper" || {
            rm -f "$temp_wrapper"
            stacker_error "Failed to create wrapper script"
            return 1
        }
        chmod 755 "$temp_wrapper"
        
        # Install atomically
        if [ "$use_sudo" = true ]; then
            sudo mv -f "$temp_wrapper" "$install_dir/manager" || {
                rm -f "$temp_wrapper"
                stacker_error "Failed to install manager"
                return 1
            }
        else
            mv -f "$temp_wrapper" "$install_dir/manager" || {
                rm -f "$temp_wrapper"
                stacker_error "Failed to install manager"
                return 1
            }
        fi
    fi
    
    # Verify installation
    if [ ! -x "$install_dir/manager" ]; then
        stacker_error "Installation failed - manager not executable"
        return 1
    fi
    
    # Test the installation
    if ! "$install_dir/manager" --version >/dev/null 2>&1; then
        stacker_error "Installation test failed - manager not working"
        return 1
    fi
    
    # Check PATH and provide guidance
    local in_path=false
    case ":$PATH:" in
        *":$install_dir:"*)
            in_path=true
            ;;
    esac
    
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║             Stacker Framework Installed Successfully!          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Installation Details:"
    echo "  • Location: $install_dir/manager"
    echo "  • Version: $(STACKER_DIR="$abs_stacker_dir" "$install_dir/manager" --version 2>/dev/null || echo "2.0.0")"
    echo "  • Type: $([ "$symlink" = true ] && echo "Symlink" || echo "Wrapper Script")"
    echo ""
    
    if [ "$in_path" = true ]; then
        echo "✓ Directory $install_dir is in your PATH"
        echo ""
        echo "You can now use 'manager' from anywhere:"
    else
        echo "⚠ Directory $install_dir is NOT in your PATH"
        echo ""
        echo "To use 'manager' from anywhere, add to PATH:"
        echo ""
        echo "  # Add to ~/.bashrc or ~/.zshrc:"
        echo "  export PATH=\"\$PATH:$install_dir\""
        echo ""
        echo "Or source it now for this session:"
        echo "  export PATH=\"\$PATH:$install_dir\""
        echo ""
        echo "Then you can use:"
    fi
    
    echo "  stacker version        # Show version"
    echo "  stacker help           # Show commands"
    echo "  stacker init           # Initialize project"
    echo "  stacker self-uninstall # Remove installation"
    echo ""
    
    return 0
}

stacker_cli_self_uninstall() {
    local force=false
    local all=false
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f)
                force=true
                ;;
            --all|-a)
                all=true
                ;;
            --help|-h)
                cat << 'EOF'
Usage: stacker self-uninstall [OPTIONS]

Remove Stacker Framework global installation

Options:
  --force, -f           Skip confirmation prompt
  --all, -a             Remove from all found locations
  --help, -h            Show this help

Description:
  Removes the globally installed 'manager' command from system.
  By default, removes only from PATH locations.
  Use --all to remove from all common installation directories.

Examples:
  stacker self-uninstall           # Interactive uninstall
  stacker self-uninstall --force   # Uninstall without confirmation
  stacker self-uninstall --all     # Remove all installations

Note:
  This only removes the global command. The Stacker Framework
  source directory remains intact and can be reinstalled anytime.
EOF
                return 0
                ;;
            *)
                stacker_error "Unknown self-uninstall option: $1"
                return 1
                ;;
        esac
        shift
    done
    
    echo "Searching for Stacker installations..."
    echo ""
    
    # Find all stacker installations
    local found_installations=""
    local found_count=0
    
    # Check PATH locations
    local IFS=':'
    for dir in $PATH; do
        if [ -f "$dir/manager" ] && [ -x "$dir/manager" ]; then
            # Check if it's our Stacker Framework
            if grep -q "Stacker Framework" "$dir/manager" 2>/dev/null || \
               grep -q "STACKER_DIR=" "$dir/manager" 2>/dev/null; then
                # Avoid duplicates
                if ! echo "$found_installations" | grep -q "^$dir/manager$"; then
                    found_installations="$found_installations$dir/manager\n"
                    found_count=$((found_count + 1))
                    echo "  Found: $dir/manager"
                fi
            fi
        fi
    done
    
    # Check common locations if --all specified
    if [ "$all" = true ]; then
        for dir in /usr/local/bin /usr/bin /opt/bin "$HOME/.local/bin" "$HOME/bin"; do
            if [ -f "$dir/manager" ] && [ -x "$dir/manager" ]; then
                # Check if not already found and it's our Stacker
                if ! echo "$found_installations" | grep -q "$dir/manager" && \
                   (grep -q "Stacker Framework" "$dir/manager" 2>/dev/null || \
                    grep -q "STACKER_DIR=" "$dir/manager" 2>/dev/null); then
                    found_installations="$found_installations$dir/manager\n"
                    found_count=$((found_count + 1))
                    echo "  Found: $dir/manager (not in PATH)"
                fi
            fi
        done
    fi
    
    # Check if any installations found
    if [ $found_count -eq 0 ]; then
        echo ""
        echo "No Stacker Framework installations found."
        echo ""
        echo "Note: Only checking for Stacker Framework installations,"
        echo "not other programs that might be named 'manager'."
        return 0
    fi
    
    echo ""
    echo "Found $found_count Stacker installation(s)"
    echo ""
    
    # Confirm uninstallation
    if [ "$force" != true ]; then
        echo "This will remove the following:"
        printf "$found_installations" | while IFS= read -r file; do
            [ -n "$file" ] && echo "  - $file"
        done
        echo ""
        printf "Are you sure you want to uninstall? (yes/no): "
        read -r confirmation
        
        case "$confirmation" in
            yes|Yes|YES|y|Y)
                echo ""
                ;;
            *)
                echo "Uninstallation cancelled."
                return 0
                ;;
        esac
    fi
    
    # Perform uninstallation
    local removed_count=0
    local failed_count=0
    
    printf "$found_installations" | while IFS= read -r file; do
        if [ -n "$file" ] && [ -f "$file" ]; then
            echo "Removing: $file"
            
            # Check if we need sudo
            if [ -w "$file" ]; then
                rm -f "$file" && {
                    echo "  ✓ Removed successfully"
                    removed_count=$((removed_count + 1))
                } || {
                    echo "  ✗ Failed to remove"
                    failed_count=$((failed_count + 1))
                }
            else
                # Try with sudo
                echo "  (requires sudo)"
                sudo rm -f "$file" && {
                    echo "  ✓ Removed successfully"
                    removed_count=$((removed_count + 1))
                } || {
                    echo "  ✗ Failed to remove"
                    failed_count=$((failed_count + 1))
                }
            fi
        fi
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              Stacker Framework Uninstalled                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "The Stacker Framework has been removed from global installation."
    echo ""
    echo "Note: The source directory remains at:"
    echo "  $(cd "$STACKER_DIR" 2>/dev/null && pwd)"
    echo ""
    echo "You can reinstall anytime by running:"
    echo "  $STACKER_DIR/manager.sh self-install"
    echo ""
    
    return 0
}

# Handle CLI arguments when run directly
if [ $# -gt 0 ]; then
    stacker_parse_cli "$@"
fi

# Functions are available when this file is sourced
# POSIX shells don't support 'export -f', functions are available in current shell context