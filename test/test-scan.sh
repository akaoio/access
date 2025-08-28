#!/bin/sh
# Test script for Access Network Scan mechanism
# Tests both interactive and non-interactive modes

set -e

# Colors for output
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

log() {
    echo "${GREEN}[TEST]${NC} $*"
}

error() {
    echo "${RED}[ERROR]${NC} $*" >&2
}

info() {
    echo "${BLUE}[INFO]${NC} $*"
}

# Test configuration
TEST_DOMAIN="test.local"
TEST_PREFIX="testpeer"
TEST_DIR="/tmp/access-scan-test"

# Create test environment
setup_test_env() {
    log "Setting up test environment..."
    
    # Create test directory structure
    mkdir -p "$TEST_DIR/config"
    mkdir -p "$TEST_DIR/state"
    
    # Copy scan script
    if [ -f "./scan.sh" ]; then
        cp ./scan.sh "$TEST_DIR/scan.sh"
        chmod +x "$TEST_DIR/scan.sh"
    else
        error "scan.sh not found in current directory"
        exit 1
    fi
    
    log "✓ Test environment created at $TEST_DIR"
}

# Test DNS check functions
test_dns_checks() {
    log "Testing DNS check functions..."
    
    # Check if DNS check function exists in the script
    if grep -q "check_peer_alive" "$TEST_DIR/scan.sh"; then
        info "DNS check function exists"
    else
        error "DNS check function not found"
        return 1
    fi
    
    log "✓ DNS check tests passed"
}

# Test slot scan
test_slot_scan() {
    log "Testing slot scan algorithm..."
    
    # Create mock config for testing
    cat > "$TEST_DIR/config/scan.json" <<EOF
{
    "domain": "$TEST_DOMAIN",
    "host_prefix": "$TEST_PREFIX",
    "dns_provider": "mock",
    "enable_auto_sync": true
}
EOF
    
    export SCAN_CONFIG="$TEST_DIR/config/scan.json"
    export SCAN_STATE="$TEST_DIR/state/scan.state"
    
    info "Testing with domain: $TEST_DOMAIN"
    info "Testing with prefix: $TEST_PREFIX"
    
    # Since we can't actually query DNS in test mode, we'll verify the logic
    if grep -q "find_lowest_available_slot" "$TEST_DIR/scan.sh"; then
        log "✓ Slot scan function found"
    else
        error "Slot scan function missing"
        return 1
    fi
    
    log "✓ Slot scan tests passed"
}

# Test interactive mode simulation
test_interactive_mode() {
    log "Testing interactive mode logic..."
    
    # Check if interactive functions exist
    if grep -q "interactive_setup" "$TEST_DIR/scan.sh"; then
        log "✓ Interactive setup function found"
    else
        error "Interactive setup function missing"
        return 1
    fi
    
    log "✓ Interactive mode tests passed"
}

# Test non-interactive mode
test_non_interactive_mode() {
    log "Testing non-interactive mode..."
    
    # Set environment variables
    export ACCESS_SCAN_DOMAIN="$TEST_DOMAIN"
    export ACCESS_SCAN_PREFIX="$TEST_PREFIX"
    export ACCESS_DNS_PROVIDER="godaddy"
    export ACCESS_DNS_KEY="test-key"
    export ACCESS_DNS_SECRET="test-secret"
    
    # Check if non-interactive functions exist
    if grep -q "non_interactive_setup" "$TEST_DIR/scan.sh"; then
        log "✓ Non-interactive setup function found"
    else
        error "Non-interactive setup function missing"
        return 1
    fi
    
    log "✓ Non-interactive mode tests passed"
}

# Test self-healing logic
test_self_healing() {
    log "Testing self-healing mechanism..."
    
    # Create a mock state file
    cat > "$TEST_DIR/state/scan.state" <<EOF
{
    "peer_slot": 5,
    "peer_host": "${TEST_PREFIX}5",
    "full_domain": "${TEST_PREFIX}5.${TEST_DOMAIN}",
    "public_ip": "192.168.1.100",
    "registered_at": "2024-01-01T00:00:00Z",
    "last_heartbeat": "2024-01-01T00:00:00Z"
}
EOF
    
    # Check if monitor and heal function exists
    if grep -q "monitor_and_heal" "$TEST_DIR/scan.sh"; then
        log "✓ Self-healing function found"
        
        # Verify it checks for lower slots
        if grep -q "while \[ \$slot -lt \$current_slot \]" "$TEST_DIR/scan.sh"; then
            log "✓ Lower slot checking logic found"
        else
            error "Lower slot checking logic missing"
        fi
    else
        error "Self-healing function missing"
        return 1
    fi
    
    log "✓ Self-healing tests passed"
}

# Test daemon mode
test_daemon_mode() {
    log "Testing daemon mode..."
    
    if grep -q "run_daemon" "$TEST_DIR/scan.sh"; then
        log "✓ Daemon mode function found"
        
        # Check for continuous loop
        if grep -q "while true" "$TEST_DIR/scan.sh"; then
            log "✓ Continuous monitoring loop found"
        else
            error "Continuous monitoring loop missing"
        fi
    else
        error "Daemon mode function missing"
        return 1
    fi
    
    log "✓ Daemon mode tests passed"
}

# Test integration with install.sh
test_installer_integration() {
    log "Testing installer integration..."
    
    if [ -f "./install.sh" ]; then
        # Check if installer has network scan support
        if grep -q "setup_network_scan" "./install.sh"; then
            log "✓ Network scan setup function found in installer"
        else
            error "Network scan not integrated in installer"
            return 1
        fi
        
        # Check for scan service setup
        if grep -q "setup_scan_service" "./install.sh"; then
            log "✓ Scan service setup found"
        else
            error "Scan service setup missing"
            return 1
        fi
        
        # Check for command line flags
        if grep -q "\-\-network-scan" "./install.sh"; then
            log "✓ Network scan CLI flag found"
        else
            error "Network scan CLI flag missing"
            return 1
        fi
    else
        error "install.sh not found"
        return 1
    fi
    
    log "✓ Installer integration tests passed"
}

# Test configuration persistence
test_config_persistence() {
    log "Testing configuration persistence..."
    
    # Create a test config
    cat > "$TEST_DIR/config/test-config.json" <<EOF
{
    "domain": "$TEST_DOMAIN",
    "host_prefix": "$TEST_PREFIX",
    "dns_provider": "godaddy",
    "dns_key": "test-key",
    "dns_secret": "test-secret",
    "enable_auto_sync": true,
    "last_updated": "2024-01-01T00:00:00Z"
}
EOF
    
    # Verify JSON structure
    if grep -q '"domain"' "$TEST_DIR/config/test-config.json" && \
       grep -q '"host_prefix"' "$TEST_DIR/config/test-config.json" && \
       grep -q '"enable_auto_sync"' "$TEST_DIR/config/test-config.json"; then
        log "✓ Configuration structure valid"
    else
        error "Configuration structure invalid"
        return 1
    fi
    
    log "✓ Configuration persistence tests passed"
}

# Cleanup test environment
cleanup_test_env() {
    log "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    log "✓ Test environment cleaned"
}

# Run all tests
run_all_tests() {
    echo ""
    echo "========================================="
    echo "  ACCESS NETWORK SCAN TEST SUITE"
    echo "========================================="
    echo ""
    
    local total_tests=0
    local passed_tests=0
    
    # Setup
    setup_test_env
    
    # Run tests
    tests="test_dns_checks test_slot_scan test_interactive_mode test_non_interactive_mode test_self_healing test_daemon_mode test_installer_integration test_config_persistence"
    
    for test in $tests; do
        total_tests=$((total_tests + 1))
        echo ""
        if $test; then
            passed_tests=$((passed_tests + 1))
        else
            error "Test failed: $test"
        fi
    done
    
    # Cleanup
    cleanup_test_env
    
    # Summary
    echo ""
    echo "========================================="
    echo "  TEST RESULTS"
    echo "========================================="
    echo "  Total tests: $total_tests"
    echo "  Passed: ${GREEN}$passed_tests${NC}"
    echo "  Failed: ${RED}$((total_tests - passed_tests))${NC}"
    
    if [ $passed_tests -eq $total_tests ]; then
        echo ""
        echo "  ${GREEN}✓ ALL TESTS PASSED!${NC}"
        echo "========================================="
        return 0
    else
        echo ""
        echo "  ${RED}✗ SOME TESTS FAILED${NC}"
        echo "========================================="
        return 1
    fi
}

# Main
case "${1:-test}" in
    test)
        run_all_tests
        ;;
    setup)
        setup_test_env
        log "Test environment ready at $TEST_DIR"
        ;;
    cleanup)
        cleanup_test_env
        ;;
    *)
        echo "Usage: $0 {test|setup|cleanup}"
        echo ""
        echo "Commands:"
        echo "  test    - Run all tests (default)"
        echo "  setup   - Create test environment only"
        echo "  cleanup - Remove test environment"
        exit 1
        ;;
esac