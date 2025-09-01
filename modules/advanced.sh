#!/bin/sh
# Module: advanced
# Description: Advanced CLI features including dry-run, diagnostics, and enhanced operations
# Dependencies: core config service
# Provides: dry-run mode, advanced diagnostics, backup/restore, JSON output

# Module metadata
STACKER_MODULE_NAME="advanced"
STACKER_MODULE_VERSION="1.0.0"
STACKER_MODULE_DEPENDENCIES="core config service"
STACKER_MODULE_LOADED=false

# Global flags for advanced features
ACCESS_DRY_RUN=${ACCESS_DRY_RUN:-false}
ACCESS_JSON_OUTPUT=${ACCESS_JSON_OUTPUT:-false}
ACCESS_VERBOSE=${ACCESS_VERBOSE:-false}

# Module initialization
advanced_init() {
    STACKER_MODULE_LOADED=true
    # Use echo instead of log since log might not be available yet
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Advanced CLI features module initialized" >> "${ACCESS_LOG:-/dev/null}" 2>/dev/null || true
    return 0
}

# Dry-run mode implementation
access_dry_run_mode() {
    ACCESS_DRY_RUN="true"
    export ACCESS_DRY_RUN
    # Use conditional log_info if available
    if command -v log_info >/dev/null 2>&1; then
        log_info "Dry-run mode enabled - no changes will be made"
    fi
}

# Check if in dry-run mode
access_is_dry_run() {
    [ "$ACCESS_DRY_RUN" = "true" ]
}

# Dry-run simulation for DNS updates
access_simulate_dns_update() {
    local provider="$1"
    local domain="$2" 
    local host="$3"
    local ip="$4"
    local record_type="${5:-A}"
    
    # Auto-detect record type if not specified
    if [ "$record_type" = "A" ] && echo "$ip" | grep -q ':'; then
        record_type="AAAA"
    fi
    
    echo ""
    echo "${BOLD}DRY-RUN: DNS Update Simulation${NC}"
    echo "Provider:    ${YELLOW}$provider${NC}"
    echo "Domain:      ${YELLOW}$domain${NC}" 
    echo "Host:        ${YELLOW}$host${NC}"
    echo "Record Type: ${YELLOW}$record_type${NC}"
    echo "New IP:      ${CYAN}$ip${NC}"
    echo ""
    
    # Simulate provider validation
    if load_provider "$provider" >/dev/null 2>&1; then
        echo "${GREEN}✓${NC} Provider validation: ${GREEN}PASS${NC}"
        
        if command -v provider_validate >/dev/null 2>&1; then
            if provider_validate; then
                echo "${GREEN}✓${NC} Provider credentials: ${GREEN}VALID${NC}"
            else
                echo "${RED}✗${NC} Provider credentials: ${RED}INVALID${NC}"
                return 1
            fi
        else
            echo "${YELLOW}!${NC} Provider credentials: ${YELLOW}CANNOT VERIFY${NC}"
        fi
    else
        echo "${RED}✗${NC} Provider validation: ${RED}FAIL${NC}"
        return 1
    fi
    
    # Simulate DNS record lookup
    local lookup_host="${host}.${domain}"
    [ "$host" = "@" ] && lookup_host="$domain"
    
    echo "${BLUE}ℹ${NC} Looking up current DNS record..."
    local current_ip
    if current_ip=$(dig +short "$lookup_host" 2>/dev/null | head -1) && [ -n "$current_ip" ]; then
        echo "${GREEN}✓${NC} Current DNS IP: ${CYAN}$current_ip${NC}"
        
        if [ "$current_ip" = "$ip" ]; then
            echo "${YELLOW}!${NC} DNS record is already up to date"
            echo "${DIM}  No update would be performed${NC}"
        else
            echo "${BLUE}ℹ${NC} DNS update required: ${CYAN}$current_ip${NC} → ${CYAN}$ip${NC}"
            echo "${GREEN}✓${NC} DNS update would be successful"
        fi
    else
        echo "${YELLOW}!${NC} Cannot retrieve current DNS record"
        echo "${BLUE}ℹ${NC} DNS update would create new record"
    fi
    
    echo ""
    echo "${GREEN}DRY-RUN COMPLETE${NC} - No actual changes were made"
    return 0
}

# Comprehensive system diagnostics
access_run_diagnostics() {
    local json_output=${1:-false}
    
    if [ "$json_output" = "true" ]; then
        access_diagnostics_json
    else
        access_diagnostics_human
    fi
}

# Human-readable diagnostics
access_diagnostics_human() {
    echo ""
    echo "${BOLD}Access System Diagnostics${NC}"
    echo ""
    echo ""
    
    # Network connectivity tests
    echo "${BOLD}Network Connectivity:${NC}"
    
    # Test internet connectivity
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "  ${GREEN}✓${NC} Internet connectivity: ${GREEN}OK${NC}"
    else
        echo "  ${RED}✗${NC} Internet connectivity: ${RED}FAILED${NC}"
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        echo "  ${GREEN}✓${NC} DNS resolution: ${GREEN}OK${NC}"
    else
        echo "  ${RED}✗${NC} DNS resolution: ${RED}FAILED${NC}"
    fi
    
    # Test IPv6 connectivity
    if ping -6 -c 1 -W 5 2001:4860:4860::8888 >/dev/null 2>&1; then
        echo "  ${GREEN}✓${NC} IPv6 connectivity: ${GREEN}OK${NC}"
    else
        echo "  ${YELLOW}!${NC} IPv6 connectivity: ${YELLOW}LIMITED/UNAVAILABLE${NC}"
    fi
    
    echo ""
    
    # IP detection tests
    echo "${BOLD}IP Detection:${NC}"
    
    local ipv4_ip
    ipv4_ip=$(detect_ipv4 2>/dev/null)
    if [ -n "$ipv4_ip" ]; then
        echo "  ${GREEN}✓${NC} IPv4 detection: ${CYAN}$ipv4_ip${NC}"
    else
        echo "  ${RED}✗${NC} IPv4 detection: ${RED}FAILED${NC}"
    fi
    
    local ipv6_ip  
    ipv6_ip=$(detect_ipv6 2>/dev/null)
    if [ -n "$ipv6_ip" ]; then
        echo "  ${GREEN}✓${NC} IPv6 detection: ${CYAN}$ipv6_ip${NC}"
    else
        echo "  ${YELLOW}!${NC} IPv6 detection: ${YELLOW}UNAVAILABLE${NC}"
    fi
    
    echo ""
    
    # Configuration validation
    echo "${BOLD}Configuration:${NC}"
    load_config
    
    if [ -f "$ACCESS_CONFIG" ]; then
        echo "  ${GREEN}✓${NC} Config file: ${GREEN}EXISTS${NC} ($ACCESS_CONFIG)"
        
        if [ -n "$PROVIDER" ]; then
            echo "  ${GREEN}✓${NC} Provider: ${YELLOW}$PROVIDER${NC}"
            
            # Test provider loading
            if load_provider "$PROVIDER" >/dev/null 2>&1; then
                echo "  ${GREEN}✓${NC} Provider loading: ${GREEN}OK${NC}"
                
                # Test provider credentials
                if command -v provider_validate >/dev/null 2>&1; then
                    if provider_validate 2>/dev/null; then
                        echo "  ${GREEN}✓${NC} Provider credentials: ${GREEN}VALID${NC}"
                    else
                        echo "  ${RED}✗${NC} Provider credentials: ${RED}INVALID${NC}"
                    fi
                else
                    echo "  ${YELLOW}!${NC} Provider validation: ${YELLOW}NOT AVAILABLE${NC}"
                fi
            else
                echo "  ${RED}✗${NC} Provider loading: ${RED}FAILED${NC}"
            fi
        else
            echo "  ${RED}✗${NC} Provider: ${RED}NOT CONFIGURED${NC}"
        fi
        
        if [ -n "$DOMAIN" ]; then
            echo "  ${GREEN}✓${NC} Domain: ${YELLOW}$DOMAIN${NC}"
        else
            echo "  ${RED}✗${NC} Domain: ${RED}NOT CONFIGURED${NC}"
        fi
        
        if [ -n "$HOST" ]; then
            echo "  ${GREEN}✓${NC} Host: ${YELLOW}$HOST${NC}"
        else
            echo "  ${YELLOW}!${NC} Host: ${YELLOW}WILL USE DEFAULT (@)${NC}"
        fi
    else
        echo "  ${RED}✗${NC} Config file: ${RED}MISSING${NC}"
    fi
    
    echo ""
    
    # Service status
    echo "${BOLD}Service Status:${NC}"
    
    # Check daemon status
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
        if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            echo "  ${GREEN}✓${NC} Watchdog daemon: ${GREEN}RUNNING${NC} (PID: $daemon_pid)"
        else
            echo "  ${YELLOW}!${NC} Watchdog daemon: ${YELLOW}STALE LOCK${NC}"
        fi
    else
        echo "  ${DIM}○${NC} Watchdog daemon: ${DIM}NOT RUNNING${NC}"
    fi
    
    # Check cron status
    if crontab -l 2>/dev/null | grep -q "access"; then
        echo "  ${GREEN}✓${NC} Cron job: ${GREEN}CONFIGURED${NC}"
    else
        echo "  ${YELLOW}!${NC} Cron job: ${YELLOW}NOT CONFIGURED${NC}"
    fi
    
    # Check last run
    if [ -f "$ACCESS_DATA_HOME/last_run" ]; then
        local last_run=$(cat "$ACCESS_DATA_HOME/last_run" 2>/dev/null)
        local current_time=$(date +%s)
        local age=$((current_time - last_run))
        local minutes_ago=$((age / 60))
        
        if [ "$age" -lt 3600 ]; then
            echo "  ${GREEN}✓${NC} Last update: ${GREEN}${minutes_ago}m ago${NC}"
        else
            local hours_ago=$((age / 3600))
            echo "  ${YELLOW}!${NC} Last update: ${YELLOW}${hours_ago}h ago${NC}"
        fi
    else
        echo "  ${YELLOW}!${NC} Last update: ${YELLOW}NEVER${NC}"
    fi
    
    echo ""
    
    # System dependencies
    echo "${BOLD}System Dependencies:${NC}"
    
    for cmd in curl wget dig nslookup jq; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  ${GREEN}✓${NC} $cmd: ${GREEN}AVAILABLE${NC}"
        else
            echo "  ${YELLOW}!${NC} $cmd: ${YELLOW}NOT FOUND${NC}"
        fi
    done
    
    echo ""
    echo "${BOLD}Diagnostics Complete${NC}"
}

# JSON diagnostics output
access_diagnostics_json() {
    local output="{"
    
    # Network tests
    local internet_ok="false"
    local dns_ok="false"
    local ipv6_ok="false"
    
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 && internet_ok="true"
    nslookup google.com >/dev/null 2>&1 && dns_ok="true"  
    ping -6 -c 1 -W 5 2001:4860:4860::8888 >/dev/null 2>&1 && ipv6_ok="true"
    
    output="$output\"network\": {\"internet\": $internet_ok, \"dns\": $dns_ok, \"ipv6\": $ipv6_ok},"
    
    # IP detection
    local ipv4_ip=$(detect_ipv4 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g')
    local ipv6_ip=$(detect_ipv6 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g')
    
    output="$output\"ip_detection\": {\"ipv4\": \"$ipv4_ip\", \"ipv6\": \"$ipv6_ip\"},"
    
    # Configuration
    load_config
    local config_exists="false"
    local provider_valid="false"
    
    [ -f "$ACCESS_CONFIG" ] && config_exists="true"
    if [ -n "$PROVIDER" ] && load_provider "$PROVIDER" >/dev/null 2>&1; then
        if command -v provider_validate >/dev/null 2>&1 && provider_validate 2>/dev/null; then
            provider_valid="true"
        fi
    fi
    
    output="$output\"configuration\": {\"config_exists\": $config_exists, \"provider\": \"${PROVIDER:-}\", \"domain\": \"${DOMAIN:-}\", \"host\": \"${HOST:-}\", \"provider_valid\": $provider_valid},"
    
    # Service status
    local daemon_running="false"
    local cron_configured="false"
    local last_run="null"
    
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
        [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null && daemon_running="true"
    fi
    
    crontab -l 2>/dev/null | grep -q "access" && cron_configured="true"
    
    if [ -f "$ACCESS_DATA_HOME/last_run" ]; then
        last_run=$(cat "$ACCESS_DATA_HOME/last_run" 2>/dev/null || echo "null")
    fi
    
    output="$output\"service\": {\"daemon_running\": $daemon_running, \"cron_configured\": $cron_configured, \"last_run\": $last_run},"
    
    # Dependencies
    local deps="["
    local first=true
    for cmd in curl wget dig nslookup jq; do
        [ "$first" = false ] && deps="$deps,"
        first=false
        
        local available="false"
        command -v "$cmd" >/dev/null 2>&1 && available="true"
        
        deps="$deps{\"name\": \"$cmd\", \"available\": $available}"
    done
    deps="$deps]"
    
    output="$output\"dependencies\": $deps}"
    
    echo "$output"
}

# Configuration backup system
access_backup_config() {
    local backup_name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local backup_dir="$ACCESS_DATA_HOME/backups"
    
    mkdir -p "$backup_dir"
    
    if [ ! -f "$ACCESS_CONFIG" ]; then
        log_error "No configuration file found to backup"
        return 1
    fi
    
    local backup_file="$backup_dir/config_$backup_name.json"
    
    # Copy configuration with metadata
    {
        echo "{"
        echo "  \"backup_info\": {"
        echo "    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "    \"version\": \"$VERSION\","
        echo "    \"hostname\": \"$(hostname)\""
        echo "  },"
        echo "  \"configuration\": $(cat "$ACCESS_CONFIG")"
        echo "}"
    } > "$backup_file"
    
    log_success "Configuration backed up to: $backup_file"
    return 0
}

# Configuration restore system
access_restore_config() {
    local backup_name="$1"
    local backup_dir="$ACCESS_DATA_HOME/backups"
    
    if [ -z "$backup_name" ]; then
        log_error "Backup name required"
        echo "Available backups:"
        ls -1 "$backup_dir"/config_*.json 2>/dev/null | sed 's/.*config_\(.*\)\.json$/  \1/' || echo "  No backups found"
        return 1
    fi
    
    local backup_file="$backup_dir/config_$backup_name.json"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup not found: $backup_file"
        return 1
    fi
    
    # Extract configuration from backup
    if command -v jq >/dev/null 2>&1; then
        jq '.configuration' "$backup_file" > "$ACCESS_CONFIG.restore"
    else
        # Fallback extraction without jq
        sed -n '/"configuration":/,/^}$/p' "$backup_file" | sed '1s/.*: //' | sed '$d' > "$ACCESS_CONFIG.restore"
    fi
    
    # Validate restored config
    if [ -s "$ACCESS_CONFIG.restore" ]; then
        # Backup current config if it exists
        if [ -f "$ACCESS_CONFIG" ]; then
            cp "$ACCESS_CONFIG" "$ACCESS_CONFIG.backup.$(date +%s)"
            log "Current config backed up"
        fi
        
        mv "$ACCESS_CONFIG.restore" "$ACCESS_CONFIG"
        log_success "Configuration restored from: $backup_file"
        return 0
    else
        rm -f "$ACCESS_CONFIG.restore"
        log_error "Failed to restore configuration"
        return 1
    fi
}

# List configuration backups
access_list_backups() {
    local backup_dir="$ACCESS_DATA_HOME/backups"
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir"/config_*.json 2>/dev/null)" ]; then
        echo "No configuration backups found"
        return 1
    fi
    
    echo "${BOLD}Available Configuration Backups:${NC}"
    echo ""
    echo ""
    
    for backup_file in "$backup_dir"/config_*.json; do
        [ -f "$backup_file" ] || continue
        
        local backup_name=$(basename "$backup_file" | sed 's/config_\(.*\)\.json$/\1/')
        local file_date=$(stat -c %Y "$backup_file" 2>/dev/null)
        local human_date=$(date -d "@$file_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date "+%Y-%m-%d %H:%M:%S")
        
        echo "  ${YELLOW}$backup_name${NC}"
        echo "    Created: $human_date"
        echo "    Size: $(wc -c < "$backup_file") bytes"
        
        # Extract backup info if available
        if command -v jq >/dev/null 2>&1; then
            local version=$(jq -r '.backup_info.version // "unknown"' "$backup_file" 2>/dev/null)
            local hostname=$(jq -r '.backup_info.hostname // "unknown"' "$backup_file" 2>/dev/null)
            echo "    Version: $version"
            echo "    Host: $hostname"
        fi
        echo ""
    done
}

# Enhanced status with metrics
access_status_detailed() {
    local json_output=${1:-false}
    
    if [ "$json_output" = "true" ]; then
        access_status_json
    else
        access_status_human_detailed
    fi
}

# Detailed human-readable status
access_status_human_detailed() {
    echo ""
    echo "${BOLD}Access Detailed Status Report${NC}"
    echo ""
    echo ""
    
    # Basic configuration (reuse existing logic but enhance)
    load_config
    
    echo "${BOLD}Configuration:${NC}"
    if [ -f "$ACCESS_CONFIG" ]; then
        echo "  File: ${GREEN}$ACCESS_CONFIG${NC}"
        echo "  Provider: ${YELLOW}${PROVIDER:-not configured}${NC}"
        echo "  Domain: ${YELLOW}${DOMAIN:-not configured}${NC}"
        echo "  Host: ${YELLOW}${HOST:-not configured}${NC}"
        
        # Show file age and size
        local config_age=$(stat -c %Y "$ACCESS_CONFIG" 2>/dev/null)
        if [ -n "$config_age" ]; then
            local current_time=$(date +%s)
            local age_seconds=$((current_time - config_age))
            local age_days=$((age_seconds / 86400))
            echo "  Last modified: ${DIM}${age_days} days ago${NC}"
        fi
        
        local config_size=$(wc -c < "$ACCESS_CONFIG" 2>/dev/null || echo "unknown")
        echo "  Size: ${DIM}${config_size} bytes${NC}"
    else
        echo "  ${RED}No configuration found${NC}"
    fi
    
    echo ""
    
    # IP detection metrics
    echo "${BOLD}IP Detection Performance:${NC}"
    local start_time=$(date +%s%N)
    local detected_ip=$(detect_ip 2>/dev/null)
    local end_time=$(date +%s%N)
    local detection_time=$(((end_time - start_time) / 1000000)) # Convert to milliseconds
    
    if [ -n "$detected_ip" ]; then
        echo "  Current IP: ${CYAN}$detected_ip${NC}"
        echo "  Detection time: ${DIM}${detection_time}ms${NC}"
        
        # Determine IP type
        if echo "$detected_ip" | grep -q ':'; then
            echo "  Type: ${YELLOW}IPv6${NC}"
        else
            echo "  Type: ${YELLOW}IPv4${NC}"
        fi
    else
        echo "  ${RED}IP detection failed${NC}"
        echo "  Detection time: ${DIM}${detection_time}ms${NC}"
    fi
    
    echo ""
    
    # Service metrics
    echo "${BOLD}Service Metrics:${NC}"
    
    # Daemon status with uptime
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
        if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            echo "  Daemon: ${GREEN}Running${NC} (PID: $daemon_pid)"
            
            # Calculate uptime
            local daemon_start=$(stat -c %Y "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
            if [ -n "$daemon_start" ]; then
                local current_time=$(date +%s)
                local uptime_seconds=$((current_time - daemon_start))
                local uptime_hours=$((uptime_seconds / 3600))
                local uptime_minutes=$(((uptime_seconds % 3600) / 60))
                echo "  Uptime: ${DIM}${uptime_hours}h ${uptime_minutes}m${NC}"
            fi
        else
            echo "  Daemon: ${YELLOW}Stale lock${NC} (PID: $daemon_pid)"
        fi
    else
        echo "  Daemon: ${DIM}Not running${NC}"
    fi
    
    # Update history
    if [ -f "$ACCESS_DATA_HOME/last_run" ]; then
        local last_run=$(cat "$ACCESS_DATA_HOME/last_run" 2>/dev/null)
        local current_time=$(date +%s)
        local age=$((current_time - last_run))
        local readable_time=$(date -d "@$last_run" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        
        echo "  Last update: ${YELLOW}$readable_time${NC}"
        echo "  Age: ${DIM}$((age / 60)) minutes ago${NC}"
    else
        echo "  Last update: ${YELLOW}Never${NC}"
    fi
    
    # Log statistics
    if [ -f "$ACCESS_LOG" ]; then
        local log_lines=$(wc -l < "$ACCESS_LOG" 2>/dev/null || echo "0")
        local log_size=$(wc -c < "$ACCESS_LOG" 2>/dev/null || echo "0")
        local log_errors=$(grep -c "ERROR:" "$ACCESS_LOG" 2>/dev/null || echo "0")
        local log_successes=$(grep -c "SUCCESS:" "$ACCESS_LOG" 2>/dev/null || echo "0")
        
        echo ""
        echo "${BOLD}Log Statistics:${NC}"
        echo "  Total entries: ${YELLOW}$log_lines${NC}"
        echo "  File size: ${DIM}$log_size bytes${NC}"
        echo "  Errors: ${RED}$log_errors${NC}"
        echo "  Successes: ${GREEN}$log_successes${NC}"
        
        if [ "$log_lines" -gt 0 ]; then
            local success_rate=$((log_successes * 100 / (log_successes + log_errors)))
            echo "  Success rate: ${CYAN}${success_rate}%${NC}"
        fi
    fi
    
    echo ""
    
    # System resource usage
    echo "${BOLD}System Resources:${NC}"
    
    # Disk usage for Access data
    local data_usage=$(du -sh "$ACCESS_DATA_HOME" 2>/dev/null | cut -f1 || echo "unknown")
    echo "  Data directory size: ${YELLOW}$data_usage${NC}"
    
    # Memory usage (if possible to determine)
    if command -v ps >/dev/null 2>&1; then
        local access_processes=$(ps aux | grep "[a]ccess" | wc -l || echo "0")
        echo "  Active processes: ${YELLOW}$access_processes${NC}"
    fi
    
    echo ""
    echo "${GREEN}Status report complete${NC}"
}

# JSON status output
access_status_json() {
    load_config
    
    # Start building JSON
    local json="{"
    
    # Basic config
    json="$json\"configuration\": {"
    json="$json\"file\": \"$ACCESS_CONFIG\","
    json="$json\"provider\": \"${PROVIDER:-}\","
    json="$json\"domain\": \"${DOMAIN:-}\","
    json="$json\"host\": \"${HOST:-}\""
    
    if [ -f "$ACCESS_CONFIG" ]; then
        local config_age=$(stat -c %Y "$ACCESS_CONFIG" 2>/dev/null || echo "null")
        local config_size=$(wc -c < "$ACCESS_CONFIG" 2>/dev/null || echo "0")
        json="$json,\"last_modified\": $config_age,"
        json="$json\"size\": $config_size"
    fi
    json="$json},"
    
    # IP detection
    local detected_ip=$(detect_ip 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g')
    local ip_type="unknown"
    if [ -n "$detected_ip" ]; then
        if echo "$detected_ip" | grep -q ':'; then
            ip_type="ipv6"
        else
            ip_type="ipv4"
        fi
    fi
    
    json="$json\"ip_detection\": {"
    json="$json\"current_ip\": \"$detected_ip\","
    json="$json\"type\": \"$ip_type\""
    json="$json},"
    
    # Service status
    local daemon_running="false"
    local daemon_pid="null"
    local daemon_uptime="null"
    
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null || echo "null")
        if [ "$daemon_pid" != "null" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            daemon_running="true"
            local daemon_start=$(stat -c %Y "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
            if [ -n "$daemon_start" ]; then
                daemon_uptime=$(($(date +%s) - daemon_start))
            fi
        fi
    fi
    
    json="$json\"service\": {"
    json="$json\"daemon_running\": $daemon_running,"
    json="$json\"daemon_pid\": $daemon_pid,"
    json="$json\"daemon_uptime\": $daemon_uptime"
    
    if [ -f "$ACCESS_DATA_HOME/last_run" ]; then
        local last_run=$(cat "$ACCESS_DATA_HOME/last_run" 2>/dev/null || echo "null")
        json="$json,\"last_run\": $last_run"
    fi
    
    json="$json},"
    
    # Log statistics
    if [ -f "$ACCESS_LOG" ]; then
        local log_lines=$(wc -l < "$ACCESS_LOG" 2>/dev/null || echo "0")
        local log_size=$(wc -c < "$ACCESS_LOG" 2>/dev/null || echo "0")
        local log_errors=$(grep -c "ERROR:" "$ACCESS_LOG" 2>/dev/null || echo "0")
        local log_successes=$(grep -c "SUCCESS:" "$ACCESS_LOG" 2>/dev/null || echo "0")
        
        json="$json\"logs\": {"
        json="$json\"total_entries\": $log_lines,"
        json="$json\"file_size\": $log_size,"
        json="$json\"errors\": $log_errors,"
        json="$json\"successes\": $log_successes"
        json="$json},"
    else
        json="$json\"logs\": null,"
    fi
    
    # System info
    local data_usage=$(du -s "$ACCESS_DATA_HOME" 2>/dev/null | cut -f1 || echo "0")
    local access_processes=$(ps aux | grep "[a]ccess" | wc -l 2>/dev/null || echo "0")
    
    json="$json\"system\": {"
    json="$json\"data_directory_kb\": $data_usage,"
    json="$json\"active_processes\": $access_processes,"
    json="$json\"timestamp\": $(date +%s)"
    json="$json}"
    
    json="$json}"
    
    echo "$json"
}

# Export public interface
advanced_list_functions() {
    echo "access_dry_run_mode access_is_dry_run access_simulate_dns_update"
    echo "access_run_diagnostics access_diagnostics_human access_diagnostics_json"
    echo "access_backup_config access_restore_config access_list_backups"  
    echo "access_status_detailed access_status_human_detailed access_status_json"
}