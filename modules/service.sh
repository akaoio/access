#!/bin/sh
# Module: service
# Description: Access-specific service monitoring and cron health management
# Dependencies: core config
# Provides: cron monitoring, sync validation, watchdog functions

# Module metadata
STACKER_MODULE_NAME="service"
STACKER_MODULE_VERSION="2.0.0"
STACKER_MODULE_DEPENDENCIES="core config"
STACKER_MODULE_LOADED=false

# Module initialization
service_init() {
    STACKER_MODULE_LOADED=true
    log "Access service monitoring module initialized"
    return 0
}

# Check if cron job is healthy and running
access_check_cron_health() {
    local service_name="${STACKER_TECH_NAME:-access}"
    local cron_status="unknown"
    local last_run="never"
    local issues=0
    
    # Check if cron service is running
    if ! pgrep -x "cron\|crond" >/dev/null 2>&1; then
        log "❌ Cron daemon not running"
        issues=$((issues + 1))
        cron_status="daemon_dead"
    else
        log "✓ Cron daemon running"
    fi
    
    # Check if our cron job exists
    if ! crontab -l 2>/dev/null | grep -q "$service_name"; then
        log "❌ Access cron job not found"
        issues=$((issues + 1))
        cron_status="job_missing"
    else
        log "✓ Access cron job configured"
        cron_status="configured"
        
        # Try to determine last cron execution
        if [ -f "$ACCESS_DATA_HOME/last_cron.log" ]; then
            last_run=$(stat -c %Y "$ACCESS_DATA_HOME/last_cron.log" 2>/dev/null)
            if [ -n "$last_run" ]; then
                local current_time=$(date +%s)
                local run_age=$((current_time - last_run))
                local minutes_ago=$((run_age / 60))
                
                if [ "$run_age" -gt 900 ]; then  # 15 minutes
                    log "⚠️ Last cron run: ${minutes_ago}m ago (may be stale)"
                    issues=$((issues + 1))
                else
                    log "✓ Last cron run: ${minutes_ago}m ago (healthy)"
                fi
            fi
        fi
    fi
    
    # Return status
    if [ "$issues" -eq 0 ]; then
        echo "healthy"
        return 0
    else
        echo "unhealthy:$cron_status"
        return 1
    fi
}

# Check DNS sync status and IP alignment
access_check_sync_status() {
    local provider="$(stacker_get_config "provider" 2>/dev/null)"
    local domain="$(stacker_get_config "domain" 2>/dev/null)"
    local host="$(stacker_get_config "host" 2>/dev/null)"
    local issues=0
    
    if [ -z "$provider" ] || [ -z "$domain" ]; then
        log "❌ Access not configured (provider/domain missing)"
        echo "unconfigured"
        return 1
    fi
    
    # Get current public IP
    local current_ip
    current_ip=$(detect_ip 2>/dev/null) || {
        log "❌ Cannot detect current public IP"
        issues=$((issues + 1))
        echo "ip_detection_failed"
        return 1
    }
    
    # Get DNS record IP
    local dns_ip
    local lookup_host="${host}.${domain}"
    [ "$host" = "@" ] && lookup_host="$domain"
    
    dns_ip=$(dig +short "$lookup_host" 2>/dev/null | head -1) || {
        log "❌ Cannot resolve DNS record for $lookup_host"
        issues=$((issues + 1))
        echo "dns_lookup_failed"
        return 1
    }
    
    # Compare IPs
    if [ "$current_ip" = "$dns_ip" ]; then
        log "✓ DNS in sync: $current_ip"
        
        # Check last successful update timestamp
        if [ -f "$ACCESS_DATA_HOME/last_success.log" ]; then
            local last_success=$(cat "$ACCESS_DATA_HOME/last_success.log" 2>/dev/null)
            local current_time=$(date +%s)
            local success_age=$((current_time - last_success))
            local hours_ago=$((success_age / 3600))
            
            if [ "$success_age" -gt 86400 ]; then  # 24 hours
                log "⚠️ Last successful sync: ${hours_ago}h ago (stale but IP matches)"
            else
                log "✓ Last successful sync: ${hours_ago}h ago (recent)"
            fi
        fi
        
        echo "synced"
        return 0
    else
        log "❌ DNS out of sync: current=$current_ip, dns=$dns_ip"
        echo "out_of_sync"
        return 1
    fi
}

# Repair broken cron job
access_repair_cron() {
    local service_name="${STACKER_TECH_NAME:-access}"
    local interval="${1:-5}"
    
    log "🔧 Attempting to repair cron job..."
    
    # Use Stacker's cron management instead of duplicating
    if command -v stacker_setup_cron_job >/dev/null 2>&1; then
        stacker_setup_cron_job "$interval"
        return $?
    else
        # Fallback if Stacker function not available
        local install_dir="$STACKER_INSTALL_DIR"
        local binary_path="$install_dir/$service_name"
        local cron_comment="# $service_name - managed by Access watchdog"
        local cron_entry="*/$interval * * * * $binary_path update >/dev/null 2>&1"
        
        log "Installing fallback cron job..."
        (crontab -l 2>/dev/null | grep -v "$service_name"; echo "$cron_comment"; echo "$cron_entry") | crontab -
        
        if crontab -l 2>/dev/null | grep -q "$service_name"; then
            log "✓ Cron job repaired successfully"
            return 0
        else
            log "❌ Failed to repair cron job"
            return 1
        fi
    fi
}

# Main watchdog function - monitors and repairs
access_watchdog_cycle() {
    log "🐕 Access watchdog cycle starting..."
    
    local cron_health
    local sync_status
    local actions_taken=0
    
    # Check cron health
    cron_health=$(access_check_cron_health)
    case "$cron_health" in
        "healthy")
            log "✓ Cron system healthy"
            ;;
        "unhealthy:daemon_dead")
            log "🚨 Cron daemon dead - cannot auto-repair system service"
            log "   Manual intervention required: sudo systemctl start cron"
            ;;
        "unhealthy:job_missing")
            log "🔧 Repairing missing cron job..."
            if access_repair_cron; then
                actions_taken=$((actions_taken + 1))
                log "✓ Cron job repaired"
            else
                log "❌ Failed to repair cron job"
            fi
            ;;
        *)
            log "⚠️ Cron health: $cron_health"
            ;;
    esac
    
    # Check sync status
    sync_status=$(access_check_sync_status)
    case "$sync_status" in
        "synced")
            log "✓ DNS sync validated"
            ;;
        "out_of_sync")
            log "🔧 DNS out of sync - triggering update..."
            # Call update directly to sync
            if access_update_dns_direct; then
                actions_taken=$((actions_taken + 1))
                log "✓ DNS sync triggered"
            else
                log "❌ Failed to sync DNS"
            fi
            ;;
        "unconfigured")
            log "⚠️ Access not configured - skipping sync check"
            ;;
        *)
            log "⚠️ Sync status: $sync_status"
            ;;
    esac
    
    # Log watchdog completion
    if [ "$actions_taken" -gt 0 ]; then
        log "🐕 Watchdog cycle complete - $actions_taken actions taken"
    else
        log "🐕 Watchdog cycle complete - all systems healthy"
    fi
    
    # Update last watchdog run timestamp
    echo "$(date +%s)" > "$ACCESS_DATA_HOME/last_watchdog.log"
}

# Direct DNS update bypassing redundancy checks
access_update_dns_direct() {
    # Bypass the redundancy logic and update directly
    local temp_redundant="$ACCESS_SKIP_REDUNDANT"
    ACCESS_SKIP_REDUNDANT="true"
    export ACCESS_SKIP_REDUNDANT
    
    # Call the main update function via the main access script  
    local result
    load_config
    if [ -n "$PROVIDER" ]; then
        ip=$(detect_ip 2>/dev/null)
        if [ $? -eq 0 ]; then
            update_with_provider "$PROVIDER" "$DOMAIN" "$HOST" "$ip"
            result=$?
        else
            log "❌ Failed to detect IP for direct update"
            result=1
        fi
    else
        log "❌ No provider configured for direct update"  
        result=1
    fi
    
    # Restore redundant setting
    ACCESS_SKIP_REDUNDANT="$temp_redundant"
    export ACCESS_SKIP_REDUNDANT
    
    return $result
}

# Enhanced daemon management
access_daemon_status_detailed() {
    local json_output=${1:-false}
    
    if [ "$json_output" = "true" ]; then
        access_daemon_status_json
        return
    fi
    
    echo "${BOLD}Access Daemon Detailed Status${NC}"
    echo "============================="
    echo ""
    
    # Check daemon process
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
        
        if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            echo "Status: ${GREEN}RUNNING${NC}"
            echo "PID: ${YELLOW}$daemon_pid${NC}"
            
            # Calculate uptime
            local daemon_start=$(stat -c %Y "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
            if [ -n "$daemon_start" ]; then
                local current_time=$(date +%s)
                local uptime_seconds=$((current_time - daemon_start))
                local uptime_hours=$((uptime_seconds / 3600))
                local uptime_minutes=$(((uptime_seconds % 3600) / 60))
                echo "Uptime: ${CYAN}${uptime_hours}h ${uptime_minutes}m${NC}"
                
                local uptime_date=$(date -d "@$daemon_start" "+%Y-%m-%d %H:%M:%S")
                echo "Started: ${DIM}$uptime_date${NC}"
            fi
            
            # Memory usage if available
            if command -v ps >/dev/null 2>&1; then
                local mem_usage=$(ps -p "$daemon_pid" -o rss= 2>/dev/null | xargs)
                if [ -n "$mem_usage" ]; then
                    local mem_mb=$((mem_usage / 1024))
                    echo "Memory: ${DIM}${mem_mb}MB${NC}"
                fi
            fi
            
        else
            echo "Status: ${RED}STALE LOCK${NC}"
            echo "Lock PID: ${YELLOW}$daemon_pid${NC} (not running)"
            echo "Action: ${YELLOW}Clean lock file to restart${NC}"
        fi
    else
        echo "Status: ${DIM}NOT RUNNING${NC}"
        echo "Lock file: ${DIM}Not found${NC}"
    fi
    
    echo ""
    
    # Check watchdog activity
    echo "${BOLD}Watchdog Activity:${NC}"
    if [ -f "$ACCESS_DATA_HOME/last_watchdog.log" ]; then
        local last_watchdog=$(cat "$ACCESS_DATA_HOME/last_watchdog.log" 2>/dev/null)
        if [ -n "$last_watchdog" ]; then
            local current_time=$(date +%s)
            local watchdog_age=$((current_time - last_watchdog))
            local minutes_ago=$((watchdog_age / 60))
            
            local last_date=$(date -d "@$last_watchdog" "+%Y-%m-%d %H:%M:%S")
            echo "Last cycle: ${CYAN}$last_date${NC} (${minutes_ago}m ago)"
            
            if [ "$watchdog_age" -lt 600 ]; then
                echo "Health: ${GREEN}ACTIVE${NC}"
            else
                echo "Health: ${YELLOW}POSSIBLY STUCK${NC}"
            fi
        fi
    else
        echo "Last cycle: ${DIM}Unknown${NC}"
        echo "Health: ${DIM}Unknown${NC}"
    fi
    
    # Show recent activity from logs
    echo ""
    echo "${BOLD}Recent Activity (last 5 entries):${NC}"
    if [ -f "$ACCESS_LOG" ]; then
        grep "watchdog\|daemon" "$ACCESS_LOG" | tail -5 | while IFS= read -r line; do
            echo "  ${DIM}$line${NC}"
        done
    else
        echo "  ${DIM}No log entries found${NC}"
    fi
}

# JSON daemon status
access_daemon_status_json() {
    local json="{"
    
    # Basic status
    local status="not_running"
    local pid="null"
    local uptime="null"
    local memory="null"
    
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null || echo "null")
        
        if [ "$pid" != "null" ] && kill -0 "$pid" 2>/dev/null; then
            status="running"
            
            # Calculate uptime
            local daemon_start=$(stat -c %Y "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
            if [ -n "$daemon_start" ]; then
                uptime=$(($(date +%s) - daemon_start))
            fi
            
            # Get memory usage
            if command -v ps >/dev/null 2>&1; then
                local mem_kb=$(ps -p "$pid" -o rss= 2>/dev/null | xargs)
                if [ -n "$mem_kb" ]; then
                    memory=$mem_kb
                fi
            fi
        else
            status="stale_lock"
        fi
    fi
    
    json="$json\"status\": \"$status\","
    json="$json\"pid\": $pid,"
    json="$json\"uptime_seconds\": $uptime,"
    json="$json\"memory_kb\": $memory,"
    
    # Watchdog info
    local last_watchdog="null"
    if [ -f "$ACCESS_DATA_HOME/last_watchdog.log" ]; then
        last_watchdog=$(cat "$ACCESS_DATA_HOME/last_watchdog.log" 2>/dev/null || echo "null")
    fi
    
    json="$json\"last_watchdog\": $last_watchdog,"
    json="$json\"timestamp\": $(date +%s)"
    json="$json}"
    
    echo "$json"
}

# Graceful daemon restart
access_daemon_restart() {
    local force=${1:-false}
    
    echo "Restarting Access daemon..."
    
    # Check if daemon is running
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
        
        if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            echo "Stopping daemon (PID: $daemon_pid)..."
            
            if [ "$force" = "true" ]; then
                # Force kill
                kill -9 "$daemon_pid" 2>/dev/null
                echo "Daemon force-stopped"
            else
                # Graceful shutdown
                kill -TERM "$daemon_pid" 2>/dev/null
                
                # Wait for graceful shutdown
                local wait_count=0
                while [ $wait_count -lt 30 ] && kill -0 "$daemon_pid" 2>/dev/null; do
                    sleep 1
                    wait_count=$((wait_count + 1))
                done
                
                if kill -0 "$daemon_pid" 2>/dev/null; then
                    echo "Graceful shutdown failed, force stopping..."
                    kill -9 "$daemon_pid" 2>/dev/null
                else
                    echo "Daemon stopped gracefully"
                fi
            fi
        fi
        
        # Clean up lock file
        rm -f "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null
    else
        echo "No daemon lock found"
    fi
    
    # Start new daemon
    echo "Starting new daemon..."
    nohup "$0" daemon >/dev/null 2>&1 &
    local new_pid=$!
    
    # Wait a moment for startup
    sleep 2
    
    # Verify it started
    if kill -0 "$new_pid" 2>/dev/null; then
        echo "Daemon restarted successfully (PID: $new_pid)"
        return 0
    else
        echo "Failed to start daemon"
        return 1
    fi
}

# Reload configuration without restarting daemon
access_daemon_reload_config() {
    echo "Reloading daemon configuration..."
    
    if [ ! -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        echo "Daemon is not running"
        return 1
    fi
    
    local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
    
    if [ -z "$daemon_pid" ] || ! kill -0 "$daemon_pid" 2>/dev/null; then
        echo "Daemon PID not valid"
        return 1
    fi
    
    # Send HUP signal to reload configuration
    if kill -HUP "$daemon_pid" 2>/dev/null; then
        echo "Configuration reload signal sent to daemon (PID: $daemon_pid)"
        
        # Create a reload marker
        echo "$(date +%s)" > "$ACCESS_DATA_HOME/last_reload.log"
        return 0
    else
        echo "Failed to send reload signal"
        return 1
    fi
}

# Stop daemon gracefully
access_daemon_stop() {
    echo "Stopping Access daemon..."
    
    if [ ! -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        echo "Daemon is not running"
        return 0
    fi
    
    local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
    
    if [ -z "$daemon_pid" ] || ! kill -0 "$daemon_pid" 2>/dev/null; then
        echo "Daemon PID not valid, cleaning lock"
        rm -f "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null
        return 0
    fi
    
    # Graceful shutdown
    kill -TERM "$daemon_pid" 2>/dev/null
    
    # Wait for graceful shutdown
    local wait_count=0
    while [ $wait_count -lt 30 ] && kill -0 "$daemon_pid" 2>/dev/null; do
        sleep 1
        wait_count=$((wait_count + 1))
        [ $((wait_count % 5)) -eq 0 ] && echo "Waiting for daemon to stop... ($wait_count/30)"
    done
    
    if kill -0 "$daemon_pid" 2>/dev/null; then
        echo "Graceful shutdown failed, force stopping..."
        kill -9 "$daemon_pid" 2>/dev/null
        sleep 1
        
        if kill -0 "$daemon_pid" 2>/dev/null; then
            echo "Force stop failed"
            return 1
        fi
    fi
    
    # Clean up
    rm -f "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null
    echo "Daemon stopped successfully"
    return 0
}

# Enhanced service health check
access_service_health_detailed() {
    echo "${BOLD}Access Service Health Check${NC}"
    echo "=========================="
    echo ""
    
    local issues=0
    local warnings=0
    
    # Check daemon
    echo "${BOLD}Daemon Status:${NC}"
    if [ -f "$ACCESS_DATA_HOME/daemon.lock" ]; then
        local daemon_pid=$(cat "$ACCESS_DATA_HOME/daemon.lock" 2>/dev/null)
        if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
            echo "  ${GREEN}✓${NC} Daemon is running (PID: $daemon_pid)"
            
            # Check responsiveness
            local start_time=$(date +%s%N)
            if kill -0 "$daemon_pid" 2>/dev/null; then
                local end_time=$(date +%s%N)
                local response_time=$(((end_time - start_time) / 1000000))
                echo "  ${GREEN}✓${NC} Daemon responsive (${response_time}ms)"
            fi
        else
            echo "  ${RED}✗${NC} Daemon has stale lock (PID: $daemon_pid)"
            issues=$((issues + 1))
        fi
    else
        echo "  ${YELLOW}!${NC} Daemon not running"
        warnings=$((warnings + 1))
    fi
    
    echo ""
    
    # Check cron health
    echo "${BOLD}Cron System:${NC}"
    local cron_health=$(access_check_cron_health)
    case "$cron_health" in
        "healthy")
            echo "  ${GREEN}✓${NC} Cron system healthy"
            ;;
        "unhealthy:daemon_dead")
            echo "  ${RED}✗${NC} Cron daemon not running"
            issues=$((issues + 1))
            ;;
        "unhealthy:job_missing")
            echo "  ${YELLOW}!${NC} Access cron job missing"
            warnings=$((warnings + 1))
            ;;
        *)
            echo "  ${YELLOW}!${NC} Cron status: $cron_health"
            warnings=$((warnings + 1))
            ;;
    esac
    
    echo ""
    
    # Check sync status
    echo "${BOLD}DNS Synchronization:${NC}"
    local sync_status=$(access_check_sync_status)
    case "$sync_status" in
        "synced")
            echo "  ${GREEN}✓${NC} DNS records are synchronized"
            ;;
        "out_of_sync")
            echo "  ${RED}✗${NC} DNS records are out of sync"
            issues=$((issues + 1))
            ;;
        "unconfigured")
            echo "  ${YELLOW}!${NC} DNS synchronization not configured"
            warnings=$((warnings + 1))
            ;;
        *)
            echo "  ${YELLOW}!${NC} Sync status: $sync_status"
            warnings=$((warnings + 1))
            ;;
    esac
    
    echo ""
    
    # Overall health summary
    echo "${BOLD}Health Summary:${NC}"
    if [ $issues -eq 0 ] && [ $warnings -eq 0 ]; then
        echo "  ${GREEN}✓ All systems healthy${NC}"
        return 0
    elif [ $issues -eq 0 ]; then
        echo "  ${YELLOW}! $warnings warning(s) found${NC}"
        return 1
    else
        echo "  ${RED}✗ $issues error(s), $warnings warning(s)${NC}"
        return 2
    fi
}

# Export public interface - focused on Access-specific monitoring
service_list_functions() {
    echo "access_check_cron_health access_check_sync_status access_repair_cron"
    echo "access_watchdog_cycle access_update_dns_direct"
    echo "access_daemon_status_detailed access_daemon_status_json access_daemon_restart"
    echo "access_daemon_reload_config access_daemon_stop access_service_health_detailed"
}