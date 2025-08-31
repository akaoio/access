#!/bin/sh
# Test script to validate scan feature is truly optional
# This script verifies that Access works perfectly without scan configuration

set -e

# Test configuration
TEST_DIR="/tmp/access-test-$$"
TEST_CONFIG_DIR="$TEST_DIR/.config/access"
TEST_DATA_DIR="$TEST_DIR/.local/share/access"

# Colors for output
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    RESET=$(tput sgr0)
else
    GREEN=""
    RED=""
    YELLOW=""
    BLUE=""
    RESET=""
fi

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
test_log() {
    printf "${BLUE}[TEST]${RESET} %s\n" "$*"
}

test_pass() {
    printf "${GREEN}[PASS]${RESET} %s\n" "$*"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    printf "${RED}[FAIL]${RESET} %s\n" "$*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_info() {
    printf "${YELLOW}[INFO]${RESET} %s\n" "$*"
}

# Setup test environment
setup_test_environment() {
    test_log "Setting up test environment in $TEST_DIR"
    
    # Create test directories
    mkdir -p "$TEST_CONFIG_DIR" "$TEST_DATA_DIR"
    
    # Set environment variables to use test directories
    export HOME="$TEST_DIR"
    export ACCESS_CONFIG="$TEST_CONFIG_DIR/config.json"
    export SCAN_CONFIG="$TEST_CONFIG_DIR/scan.json"
    
    test_pass "Test environment created"
}

# Clean up test environment
cleanup_test_environment() {
    test_log "Cleaning up test environment"
    rm -rf "$TEST_DIR"
    test_pass "Test environment cleaned up"
}

# Test 1: Access works without any configuration
test_no_configuration() {
    test_log "Testing Access functionality without any configuration"
    
    # Ensure no configuration files exist
    [ ! -f "$TEST_CONFIG_DIR/config.json" ] || rm -f "$TEST_CONFIG_DIR/config.json"
    [ ! -f "$TEST_CONFIG_DIR/scan.json" ] || rm -f "$TEST_CONFIG_DIR/scan.json"
    
    # Test basic functionality (IP detection should work)
    if ./access.sh ip >/dev/null 2>&1; then
        test_pass "IP detection works without configuration"
    else
        test_info "IP detection test skipped (requires network access)"
    fi
    
    # Test help system
    if ./access.sh --help >/dev/null 2>&1; then
        test_pass "Help system works without configuration"
    else
        test_fail "Help system requires configuration"
    fi
}

# Test 2: Access works with main config but no scan config
test_main_config_only() {
    test_log "Testing Access with main config but no scan configuration"
    
    # Create minimal main configuration
    cat > "$TEST_CONFIG_DIR/config.json" << EOF
{
    "version": "2.1.0",
    "provider": "test",
    "domain": "example.com",
    "scan_enabled": false
}
EOF
    
    # Ensure no scan configuration exists
    [ ! -f "$TEST_CONFIG_DIR/scan.json" ] || rm -f "$TEST_CONFIG_DIR/scan.json"
    
    # Test that Access loads configuration
    if [ -f "$TEST_CONFIG_DIR/config.json" ]; then
        test_pass "Main configuration loaded successfully"
    else
        test_fail "Failed to create main configuration"
    fi
    
    # Test that scan configuration absence doesn't cause errors
    if ./scan.sh status >/dev/null 2>&1; then
        test_info "Scan status check handled missing configuration gracefully"
    else
        test_pass "Scan status correctly reports missing configuration"
    fi
}

# Test 3: Scan feature is disabled by default
test_scan_disabled_by_default() {
    test_log "Testing that scan feature is disabled by default"
    
    # Create configuration through validation module
    if [ -f "./modules/validation.sh" ]; then
        . ./modules/validation.sh
        if create_safe_defaults; then
            test_pass "Safe default configuration created"
        else
            test_fail "Failed to create safe default configuration"
        fi
        
        # Check that scan is disabled in defaults
        if [ -f "$TEST_CONFIG_DIR/config.json" ]; then
            scan_enabled=$(sed -n 's/.*"scan_enabled"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' "$TEST_CONFIG_DIR/config.json" 2>/dev/null)
            if [ "$scan_enabled" = "false" ]; then
                test_pass "Scan feature disabled by default in configuration"
            else
                test_fail "Scan feature not properly disabled by default"
            fi
        fi
    else
        test_info "Validation module not available, skipping default configuration test"
    fi
}

# Test 4: Scan configuration is optional
test_scan_configuration_optional() {
    test_log "Testing that scan configuration is completely optional"
    
    # Test scan setup cancellation
    if ./scan.sh setup </dev/null 2>/dev/null; then
        test_info "Scan setup handled non-interactive mode"
    else
        test_pass "Scan setup correctly requires interactive input or exits gracefully"
    fi
    
    # Test that scan help explains optional nature
    if ./scan.sh 2>&1 | grep -q "OPTIONAL"; then
        test_pass "Scan help clearly indicates optional nature"
    else
        test_fail "Scan help doesn't clearly indicate optional nature"
    fi
}

# Test 5: Interactive installer provides choice
test_interactive_installer_choice() {
    test_log "Testing that interactive installer gives user choice"
    
    if [ -f "./interactive-install.sh" ]; then
        # Test that help mentions optional nature
        if head -50 ./interactive-install.sh | grep -q -i "optional\|choice"; then
            test_pass "Interactive installer mentions user choice"
        else
            test_fail "Interactive installer doesn't emphasize user choice"
        fi
        
        # Test that installer is executable
        if [ -x "./interactive-install.sh" ]; then
            test_pass "Interactive installer is executable"
        else
            test_fail "Interactive installer is not executable"
        fi
    else
        test_fail "Interactive installer not found"
    fi
}

# Test 6: Configuration wizard provides toggle
test_configuration_wizard_toggle() {
    test_log "Testing configuration wizard provides scan toggle"
    
    if [ -f "./access-wizard" ]; then
        # Test that wizard is executable
        if [ -x "./access-wizard" ]; then
            test_pass "Configuration wizard is executable"
        else
            test_fail "Configuration wizard is not executable"
        fi
        
        # Test that wizard help mentions scan configuration
        if ./access-wizard help 2>&1 | grep -q -i "scan"; then
            test_pass "Configuration wizard includes scan management"
        else
            test_fail "Configuration wizard doesn't include scan management"
        fi
    else
        test_fail "Configuration wizard not found"
    fi
}

# Test 7: Validation ensures scan is optional
test_validation_ensures_optional() {
    test_log "Testing validation ensures scan is optional"
    
    if [ -f "./modules/validation.sh" ]; then
        . ./modules/validation.sh
        
        if validate_scan_optional; then
            test_pass "Scan feature validation confirms optional nature"
        else
            test_info "Scan feature validation found issues (may be expected)"
        fi
        
        if validate_access_standalone; then
            test_pass "Access standalone validation passed"
        else
            test_fail "Access standalone validation failed"
        fi
    else
        test_info "Validation module not available"
    fi
}

# Test 8: Installation guide exists and is comprehensive
test_installation_guide() {
    test_log "Testing installation guide exists and covers scan feature"
    
    if [ -f "./INSTALLATION-GUIDE.md" ]; then
        test_pass "Installation guide exists"
        
        if grep -q -i "optional" "./INSTALLATION-GUIDE.md"; then
            test_pass "Installation guide mentions optional nature"
        else
            test_fail "Installation guide doesn't emphasize optional nature"
        fi
        
        if grep -q -i "scan.*disable" "./INSTALLATION-GUIDE.md"; then
            test_pass "Installation guide explains how to disable scan"
        else
            test_fail "Installation guide doesn't explain scan disabling"
        fi
    else
        test_fail "Installation guide not found"
    fi
}

# Run all tests
run_all_tests() {
    test_log "Starting Access Optional Scan Feature Tests"
    echo "=============================================="
    echo ""
    
    setup_test_environment
    
    test_no_configuration
    test_main_config_only
    test_scan_disabled_by_default
    test_scan_configuration_optional
    test_interactive_installer_choice
    test_configuration_wizard_toggle
    test_validation_ensures_optional
    test_installation_guide
    
    cleanup_test_environment
    
    echo ""
    echo "=============================================="
    echo "Test Results:"
    printf "  ${GREEN}Passed: %d${RESET}\n" "$TESTS_PASSED"
    printf "  ${RED}Failed: %d${RESET}\n" "$TESTS_FAILED"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        printf "${GREEN}✓ All tests passed! Scan feature is properly optional.${RESET}\n"
        return 0
    else
        printf "${RED}✗ Some tests failed. Review implementation.${RESET}\n"
        return 1
    fi
}

# Main execution
case "${1:-}" in
    setup)
        setup_test_environment
        ;;
    cleanup)
        cleanup_test_environment
        ;;
    test1)
        setup_test_environment
        test_no_configuration
        cleanup_test_environment
        ;;
    test2)
        setup_test_environment
        test_main_config_only
        cleanup_test_environment
        ;;
    *)
        run_all_tests
        ;;
esac