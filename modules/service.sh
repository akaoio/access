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

# Export public interface - focused on Access-specific monitoring
service_list_functions() {
    echo "access_check_cron_health access_check_sync_status access_repair_cron"
    echo "access_watchdog_cycle access_update_dns_direct"
}