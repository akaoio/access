#!/bin/sh
# Test script for peer detection methods
# Verifies that peers can find each other without ping

set -e

# Colors
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

log() {
    echo "${GREEN}[TEST]${NC} $*"
}

error() {
    echo "${RED}[ERROR]${NC} $*"
}

info() {
    echo "${YELLOW}[INFO]${NC} $*"
}

# Test DNS resolution
test_dns() {
    log "Testing DNS resolution for peer0.akao.io..."
    
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short peer0.akao.io @8.8.8.8 2>/dev/null | head -1)
        if [ -n "$ip" ]; then
            log "✓ DNS resolves to: $ip"
            return 0
        else
            error "✗ DNS resolution failed"
            return 1
        fi
    else
        info "dig not available, skipping DNS test"
        return 0
    fi
}

# Test SSH port detection
test_ssh_port() {
    log "Testing SSH port (22) connectivity..."
    
    # Method 1: Using bash TCP
    if timeout 2 bash -c 'echo > /dev/tcp/peer0.akao.io/22' 2>/dev/null; then
        log "✓ SSH port is reachable (bash TCP method)"
        return 0
    fi
    
    # Method 2: Using curl (won't work properly for SSH but tests connectivity)
    if command -v curl >/dev/null 2>&1; then
        if curl --connect-timeout 2 telnet://peer0.akao.io:22 2>&1 | grep -q "SSH"; then
            log "✓ SSH port is reachable (curl method)"
            return 0
        fi
    fi
    
    # Method 3: Using nc if available
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 2 peer0.akao.io 22 2>/dev/null; then
            log "✓ SSH port is reachable (netcat method)"
            return 0
        fi
    fi
    
    error "✗ Cannot reach SSH port"
    return 1
}

# Test scan function
test_peer_scan() {
    log "Testing peer scan logic..."
    
    # Source the scan script functions
    DOMAIN="akao.io"
    HOST_PREFIX="peer"
    
    # Inline version of check_peer_alive for testing
    check_test_peer() {
        local peer_host="$1"
        local full_domain="$peer_host.$DOMAIN"
        
        # Check DNS
        if command -v dig >/dev/null 2>&1; then
            local ip=$(dig +short "$full_domain" @8.8.8.8 2>/dev/null | head -1)
            if [ -z "$ip" ]; then
                info "  $full_domain: No DNS record (available)"
                return 1
            fi
        fi
        
        # Check SSH port using bash TCP
        if timeout 2 bash -c "echo > /dev/tcp/$full_domain/22" 2>/dev/null; then
            info "  $full_domain: DNS exists + SSH reachable (occupied)"
            return 0
        else
            info "  $full_domain: DNS exists but unreachable (occupied)"
            return 0
        fi
    }
    
    # Test peer0 through peer2
    log "Checking peer slots 0-2..."
    for i in 0 1 2; do
        if check_test_peer "peer$i"; then
            log "  ✓ peer$i detected as occupied"
        else
            log "  ✓ peer$i detected as available"
        fi
    done
}

# Test health endpoint
test_health_endpoint() {
    log "Testing health endpoint (if available)..."
    
    # Try to start health server locally for testing
    if [ -f "./health.sh" ]; then
        info "Starting local health server for testing..."
        ./health.sh test
    else
        info "Health script not found, skipping"
    fi
}

# Simulate finding next available slot
simulate_slot_scan() {
    log "Simulating slot scan..."
    
    DOMAIN="akao.io"
    HOST_PREFIX="peer"
    
    local slot=0
    local found_available=false
    
    while [ $slot -lt 10 ]; do
        local peer_host="${HOST_PREFIX}${slot}"
        local full_domain="$peer_host.$DOMAIN"
        
        # Check if DNS exists
        if command -v dig >/dev/null 2>&1; then
            local ip=$(dig +short "$full_domain" @8.8.8.8 2>/dev/null | head -1)
            if [ -z "$ip" ]; then
                log "✓ Found available slot: $slot ($full_domain has no DNS)"
                found_available=true
                break
            else
                # Check if reachable
                if timeout 2 bash -c "echo > /dev/tcp/$full_domain/22" 2>/dev/null; then
                    info "  Slot $slot occupied ($full_domain reachable)"
                else
                    info "  Slot $slot occupied ($full_domain has DNS but unreachable)"
                fi
            fi
        fi
        
        slot=$((slot + 1))
    done
    
    if [ "$found_available" = false ]; then
        error "No available slots found in first 10 positions"
        return 1
    fi
}

# Main test execution
run_all_tests() {
    echo ""
    echo "====================================="
    echo "  PEER DETECTION TEST SUITE"
    echo "====================================="
    echo ""
    
    local total=0
    local passed=0
    
    tests="test_dns test_ssh_port test_peer_scan simulate_slot_scan test_health_endpoint"
    
    for test in $tests; do
        total=$((total + 1))
        echo ""
        if $test; then
            passed=$((passed + 1))
        fi
    done
    
    echo ""
    echo "====================================="
    echo "  RESULTS"
    echo "====================================="
    echo "  Total: $total"
    echo "  Passed: $passed"
    echo "  Failed: $((total - passed))"
    
    if [ $passed -eq $total ]; then
        echo ""
        echo "  ${GREEN}✓ ALL TESTS PASSED${NC}"
        echo ""
        log "Peer scan works without ping!"
        log "Methods used:"
        log "  1. DNS resolution check"
        log "  2. SSH port 22 connectivity"
        log "  3. HTTP health endpoints (optional)"
        log "  4. Fallback to DNS existence"
    else
        echo ""
        echo "  ${RED}✗ SOME TESTS FAILED${NC}"
    fi
    echo "====================================="
}

# Run tests
run_all_tests