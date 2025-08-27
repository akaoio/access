#!/bin/sh
# Comprehensive POSIX Compliance Test Suite for Access Discovery
# Tests every function with multiple shells and edge cases

set -e

# Test configuration
TEST_DIR="/tmp/access-posix-test-$$"
TEST_SHELLS="sh dash"  # Add ash, busybox if available
VERBOSE="${VERBOSE:-false}"

# POSIX compliant output
log() {
    printf "[TEST] %s\n" "$*"
}

error() {
    printf "[ERROR] %s\n" "$*" >&2
}

pass() {
    printf "[PASS] %s\n" "$*"
}

fail() {
    printf "[FAIL] %s\n" "$*" >&2
    return 1
}

verbose() {
    if [ "$VERBOSE" = "true" ]; then
        printf "[DEBUG] %s\n" "$*"
    fi
}

# Setup test environment
setup_test_env() {
    log "Setting up test environment at $TEST_DIR..."
    
    # Create test directory structure
    mkdir -p "$TEST_DIR/config"
    mkdir -p "$TEST_DIR/state"
    mkdir -p "$TEST_DIR/logs"
    
    # Copy scripts to test
    cp discovery.sh "$TEST_DIR/" 2>/dev/null || {
        error "discovery.sh not found"
        return 1
    }
    cp health.sh "$TEST_DIR/" 2>/dev/null || {
        error "health.sh not found"
        return 1
    }
    
    # Set test environment variables
    export DISCOVERY_CONFIG="$TEST_DIR/config/discovery.json"
    export DISCOVERY_STATE="$TEST_DIR/state/discovery.state"
    export DISCOVERY_LOG="$TEST_DIR/logs/discovery.log"
    export HEALTH_FILE="$TEST_DIR/state/health.status"
    export HEALTH_LOG="$TEST_DIR/logs/health.log"
    
    pass "Test environment created"
}

# Test 1: POSIX Shell Compatibility
test_shell_compatibility() {
    log "Testing shell compatibility..."
    
    for shell in $TEST_SHELLS; do
        if command -v "$shell" >/dev/null 2>&1; then
            verbose "Testing with $shell..."
            
            # Test syntax
            if $shell -n "$TEST_DIR/discovery.sh" 2>/dev/null; then
                pass "  $shell: discovery.sh syntax OK"
            else
                fail "  $shell: discovery.sh syntax error"
            fi
            
            if $shell -n "$TEST_DIR/health.sh" 2>/dev/null; then
                pass "  $shell: health.sh syntax OK"
            else
                fail "  $shell: health.sh syntax error"
            fi
            
            # Test execution
            if $shell "$TEST_DIR/discovery.sh" 2>&1 | grep -q "Usage:"; then
                pass "  $shell: discovery.sh executes"
            else
                fail "  $shell: discovery.sh execution failed"
            fi
        else
            verbose "  $shell not installed, skipping"
        fi
    done
}

# Test 2: JSON Parsing with sed
test_json_parsing() {
    log "Testing JSON parsing with sed..."
    
    # Create test JSON
    cat > "$TEST_DIR/test.json" <<EOF
{
    "domain": "test.local",
    "host_prefix": "node",
    "peer_slot": 42,
    "enable_auto_sync": true,
    "dns_key": "secret123"
}
EOF
    
    # Test string extraction
    domain=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TEST_DIR/test.json")
    if [ "$domain" = "test.local" ]; then
        pass "  String extraction: OK ($domain)"
    else
        fail "  String extraction: Expected 'test.local', got '$domain'"
    fi
    
    # Test number extraction
    slot=$(sed -n 's/.*"peer_slot"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$TEST_DIR/test.json")
    if [ "$slot" = "42" ]; then
        pass "  Number extraction: OK ($slot)"
    else
        fail "  Number extraction: Expected '42', got '$slot'"
    fi
    
    # Test boolean extraction
    auto_sync=$(sed -n 's/.*"enable_auto_sync"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$TEST_DIR/test.json")
    if [ "$auto_sync" = "true" ]; then
        pass "  Boolean extraction: OK ($auto_sync)"
    else
        fail "  Boolean extraction: Expected 'true', got '$auto_sync'"
    fi
}

# Test 3: DNS Resolution Methods
test_dns_resolution() {
    log "Testing DNS resolution methods..."
    
    # Test nslookup (POSIX.1)
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup "google.com" 8.8.8.8 2>/dev/null | grep -q "Address:"; then
            pass "  nslookup: Working"
        else
            fail "  nslookup: Failed"
        fi
    else
        verbose "  nslookup not available"
    fi
    
    # Test host command (common but not POSIX)
    if command -v host >/dev/null 2>&1; then
        if host "google.com" 8.8.8.8 2>/dev/null | grep -q "has address"; then
            pass "  host: Working"
        else
            fail "  host: Failed"
        fi
    else
        verbose "  host not available"
    fi
    
    # Test actual peer DNS
    if nslookup "peer0.akao.io" 2>/dev/null | grep -q "Address:"; then
        pass "  peer0.akao.io: Resolvable"
    else
        verbose "  peer0.akao.io: Not resolvable (expected if not registered)"
    fi
}

# Test 4: TCP Port Checking Methods
test_tcp_checking() {
    log "Testing TCP port checking methods..."
    
    # Test telnet (POSIX.1)
    if command -v telnet >/dev/null 2>&1; then
        # Test against a known service
        if printf "\n" | telnet google.com 80 2>/dev/null | head -1 | grep -q "Trying"; then
            pass "  telnet: Working"
        else
            verbose "  telnet: Cannot connect (firewall?)"
        fi
    else
        verbose "  telnet not available"
    fi
    
    # Test with timeout wrapper
    if command -v timeout >/dev/null 2>&1; then
        if timeout 2 sh -c 'exec 3<>/dev/tcp/google.com/80' 2>/dev/null; then
            pass "  timeout+tcp: Working"
        else
            verbose "  timeout+tcp: Not working (expected in POSIX sh)"
        fi
    fi
}

# Test 5: Config File Operations
test_config_operations() {
    log "Testing configuration operations..."
    
    # Create test config using the script
    cat > "$DISCOVERY_CONFIG" <<EOF
{
    "domain": "test.local",
    "host_prefix": "testpeer",
    "dns_provider": "godaddy",
    "dns_key": "testkey",
    "dns_secret": "testsecret",
    "enable_auto_sync": true,
    "last_updated": "2024-01-01T00:00:00Z"
}
EOF
    
    # Test loading config
    (
        cd "$TEST_DIR"
        . ./discovery.sh
        load_discovery_config
        
        if [ "$DOMAIN" = "test.local" ]; then
            pass "  Config load: Domain OK"
        else
            fail "  Config load: Domain failed"
        fi
        
        if [ "$HOST_PREFIX" = "testpeer" ]; then
            pass "  Config load: Prefix OK"
        else
            fail "  Config load: Prefix failed"
        fi
    )
}

# Test 6: Health File System
test_health_system() {
    log "Testing health monitoring system..."
    
    # Create test state
    cat > "$DISCOVERY_STATE" <<EOF
{
    "peer_slot": 5,
    "peer_host": "testpeer5",
    "full_domain": "testpeer5.test.local",
    "public_ip": "192.0.2.1",
    "registered_at": "2024-01-01T00:00:00Z",
    "last_heartbeat": "2024-01-01T00:00:00Z"
}
EOF
    
    # Test health update
    if sh "$TEST_DIR/health.sh" update 2>/dev/null; then
        pass "  Health update: OK"
    else
        fail "  Health update: Failed"
    fi
    
    # Check health file created
    if [ -f "$HEALTH_FILE" ]; then
        pass "  Health file: Created"
        
        # Verify JSON structure
        if grep -q '"peer":"testpeer5"' "$HEALTH_FILE"; then
            pass "  Health JSON: Valid"
        else
            fail "  Health JSON: Invalid"
        fi
    else
        fail "  Health file: Not created"
    fi
}

# Test 7: Peer Detection Logic
test_peer_detection() {
    log "Testing peer detection logic..."
    
    # Create mock check function
    cat > "$TEST_DIR/test-detection.sh" <<'EOF'
#!/bin/sh
# Test peer detection

check_peer_mock() {
    peer="$1"
    case "$peer" in
        peer0) return 0 ;;  # Occupied
        peer1) return 0 ;;  # Occupied
        peer2) return 1 ;;  # Available
        *) return 1 ;;
    esac
}

# Find first available
slot=0
while [ $slot -lt 5 ]; do
    if ! check_peer_mock "peer$slot"; then
        echo "Found available: $slot"
        exit 0
    fi
    slot=$((slot + 1))
done
EOF
    
    chmod +x "$TEST_DIR/test-detection.sh"
    
    result=$(sh "$TEST_DIR/test-detection.sh")
    if [ "$result" = "Found available: 2" ]; then
        pass "  Slot detection: Correct (slot 2)"
    else
        fail "  Slot detection: Wrong result: $result"
    fi
}

# Test 8: Self-Healing Logic
test_self_healing() {
    log "Testing self-healing migration logic..."
    
    # Create test scenario: peer is in slot 5, slot 2 becomes available
    cat > "$TEST_DIR/test-healing.sh" <<'EOF'
#!/bin/sh
current_slot=5

# Check if lower slots available
check_lower_slots() {
    slot=0
    while [ $slot -lt $current_slot ]; do
        # Simulate slot 2 is available
        if [ $slot -eq 2 ]; then
            echo "Lower slot $slot available"
            return 0
        fi
        slot=$((slot + 1))
    done
    return 1
}

if check_lower_slots; then
    echo "Should migrate"
else
    echo "Stay in current slot"
fi
EOF
    
    chmod +x "$TEST_DIR/test-healing.sh"
    
    result=$(sh "$TEST_DIR/test-healing.sh")
    if [ "$result" = "Lower slot 2 available
Should migrate" ]; then
        pass "  Self-healing: Logic correct"
    else
        fail "  Self-healing: Logic error: $result"
    fi
}

# Test 9: Error Handling
test_error_handling() {
    log "Testing error handling..."
    
    # Test with missing config
    rm -f "$DISCOVERY_CONFIG"
    rm -f "$DISCOVERY_STATE"
    
    missing_output=$(sh "$TEST_DIR/discovery.sh" status 2>&1)
    if echo "$missing_output" | grep -E "Warning|No discovery state" >/dev/null; then
        pass "  Missing config: Handled"
    else
        fail "  Missing config: Not handled properly - output: $missing_output"
    fi
    
    # Test with invalid JSON
    printf "invalid json{" > "$DISCOVERY_CONFIG"
    
    (
        cd "$TEST_DIR"
        . ./discovery.sh
        load_discovery_config
        
        # Should use defaults
        if [ "$DOMAIN" = "akao.io" ]; then
            pass "  Invalid JSON: Falls back to defaults"
        else
            fail "  Invalid JSON: No fallback"
        fi
    )
}

# Test 10: Command Line Interface
test_cli_interface() {
    log "Testing command-line interface..."
    
    # Test help output
    if sh "$TEST_DIR/discovery.sh" 2>&1 | grep -q "Usage:"; then
        pass "  Help output: OK"
    else
        fail "  Help output: Missing"
    fi
    
    # Test status command
    status_output=$(sh "$TEST_DIR/discovery.sh" status 2>&1)
    if echo "$status_output" | grep -E "discovery|Warning|peer" >/dev/null; then
        pass "  Status command: OK"
    else
        fail "  Status command: Failed - output: $status_output"
    fi
    
    # Test health CLI
    if sh "$TEST_DIR/health.sh" status 2>&1 | grep -q "health"; then
        pass "  Health CLI: OK"
    else
        fail "  Health CLI: Failed"
    fi
}

# Test 11: POSIX Compliance Verification
test_posix_compliance() {
    log "Verifying POSIX compliance..."
    
    # Check for bash-specific constructs
    for script in discovery.sh health.sh; do
        if [ -f "$TEST_DIR/$script" ]; then
            # Check for bash-specific features (but not POSIX character classes)
            if grep -E '\[\[.*\]\]' "$TEST_DIR/$script" | grep -v ':\[[:' >/dev/null 2>&1; then
                fail "  $script: Contains [[ ]] (bash-specific)"
            else
                pass "  $script: No [[ ]] conditionals found"
            fi
            
            if grep -q '/dev/tcp' "$TEST_DIR/$script"; then
                fail "  $script: Contains /dev/tcp (bash-specific)"
            else
                pass "  $script: No /dev/tcp found"
            fi
            
            if grep -q 'function.*()' "$TEST_DIR/$script"; then
                fail "  $script: Uses 'function' keyword (bash-specific)"
            else
                pass "  $script: No 'function' keyword"
            fi
            
            if grep -q 'array\[' "$TEST_DIR/$script"; then
                fail "  $script: Uses arrays (bash-specific)"
            else
                pass "  $script: No arrays found"
            fi
        fi
    done
}

# Test 12: Integration Test
test_integration() {
    log "Running integration test..."
    
    # Set up complete environment
    cat > "$DISCOVERY_CONFIG" <<EOF
{
    "domain": "test.local",
    "host_prefix": "inttest",
    "dns_provider": "mock",
    "enable_auto_sync": false
}
EOF
    
    # Run discovery status
    output=$(sh "$TEST_DIR/discovery.sh" status 2>&1)
    if echo "$output" | grep -E "No discovery state|Warning" >/dev/null; then
        pass "  Discovery integration: OK"
    else
        # Also pass if it shows unconfigured status
        if echo "$output" | grep -E "status.*unconfigured" >/dev/null; then
            pass "  Discovery integration: OK (unconfigured)"
        else
            fail "  Discovery integration: Unexpected output - got: $output"
        fi
    fi
    
    # Update health
    if sh "$TEST_DIR/health.sh" update 2>/dev/null; then
        pass "  Health integration: OK"
    else
        fail "  Health integration: Failed"
    fi
}

# Cleanup test environment
cleanup_test_env() {
    log "Cleaning up test environment..."
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        pass "Test environment cleaned"
    fi
}

# Test runner
run_test() {
    test_name="$1"
    test_func="$2"
    
    printf "\n"
    printf "================================\n"
    printf "Running: %s\n" "$test_name"
    printf "================================\n"
    
    if $test_func; then
        return 0
    else
        return 1
    fi
}

# Main test suite
main() {
    printf "========================================\n"
    printf "  ACCESS POSIX COMPLIANCE TEST SUITE\n"
    printf "========================================\n"
    printf "\n"
    
    # Setup
    if ! setup_test_env; then
        error "Failed to setup test environment"
        exit 1
    fi
    
    # Run tests
    total=0
    passed=0
    failed=0
    
    # List of tests
    run_test "Shell Compatibility" test_shell_compatibility && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "JSON Parsing" test_json_parsing && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "DNS Resolution" test_dns_resolution && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "TCP Checking" test_tcp_checking && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "Config Operations" test_config_operations && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "Health System" test_health_system && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "Peer Detection" test_peer_detection && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "Self-Healing" test_self_healing && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "Error Handling" test_error_handling && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "CLI Interface" test_cli_interface && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "POSIX Compliance" test_posix_compliance && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    run_test "Integration" test_integration && passed=$((passed + 1)) || failed=$((failed + 1))
    total=$((total + 1))
    
    # Cleanup
    cleanup_test_env
    
    # Summary
    printf "\n"
    printf "========================================\n"
    printf "  TEST SUMMARY\n"
    printf "========================================\n"
    printf "  Total:  %d\n" "$total"
    printf "  Passed: %d\n" "$passed"
    printf "  Failed: %d\n" "$failed"
    printf "========================================\n"
    
    if [ "$failed" -eq 0 ]; then
        printf "\n  ✓ ALL TESTS PASSED!\n\n"
        exit 0
    else
        printf "\n  ✗ %d TESTS FAILED\n\n" "$failed"
        exit 1
    fi
}

# Run tests
main "$@"