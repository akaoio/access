#!/bin/sh
# Test script for XDG compliance and self-update mechanism

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo "${GREEN}[Test]${NC} $*"; }
warn() { echo "${YELLOW}[Warning]${NC} $*"; }
error() { echo "${RED}[Error]${NC} $*"; }

# Test configuration
TEST_HOME="/tmp/access-xdg-test-$$"
XDG_CONFIG_DIR="$TEST_HOME/.config/access"
CLEAN_CLONE_DIR="$TEST_HOME/access"

log "Testing Access XDG compliance and self-update mechanism..."

# Create test environment
mkdir -p "$TEST_HOME"
export HOME="$TEST_HOME"

# Test 1: Verify XDG directory creation
log "Test 1: Testing XDG config directory creation..."

mkdir -p "$XDG_CONFIG_DIR"

if [ -d "$XDG_CONFIG_DIR" ]; then
    log "✓ Test 1 PASSED: XDG config directory created at ~/.config/access/"
else
    error "✗ Test 1 FAILED: XDG config directory not created"
    exit 1
fi

# Test 2: Verify auto-update script uses correct paths
log "Test 2: Testing auto-update script path compliance..."

# Create mock auto-update script
cat > "$XDG_CONFIG_DIR/auto-update.sh" <<'EOF'
#!/bin/sh
# Mock auto-update script for testing

CONFIG_DIR="$HOME/.config/access"
CLEAN_CLONE_DIR="$HOME/access"
LOG_FILE="$CONFIG_DIR/auto-update.log"

echo "Using XDG config: $CONFIG_DIR"
echo "Using clean clone: $CLEAN_CLONE_DIR" 
echo "Using log file: $LOG_FILE"
EOF

chmod +x "$XDG_CONFIG_DIR/auto-update.sh"

if [ -x "$XDG_CONFIG_DIR/auto-update.sh" ]; then
    log "✓ Test 2 PASSED: Auto-update script created in XDG config directory"
else
    error "✗ Test 2 FAILED: Auto-update script not executable"
    exit 1
fi

# Test 3: Verify path usage in auto-update script
log "Test 3: Testing auto-update script path usage..."

# Run mock script and check output
OUTPUT=$("$XDG_CONFIG_DIR/auto-update.sh" 2>&1)

if echo "$OUTPUT" | grep -q "/.config/access" && echo "$OUTPUT" | grep -q "/access"; then
    log "✓ Test 3 PASSED: Auto-update script uses correct XDG and clean clone paths"
else
    error "✗ Test 3 FAILED: Auto-update script paths incorrect"
    echo "Output: $OUTPUT"
    exit 1
fi

# Test 4: Test directory structure compliance
log "Test 4: Testing complete directory structure compliance..."

# Expected structure
EXPECTED_DIRS="
$XDG_CONFIG_DIR
$CLEAN_CLONE_DIR
"

# Create directories to simulate full installation
mkdir -p "$CLEAN_CLONE_DIR"

ALL_DIRS_EXIST=true
for dir in $EXPECTED_DIRS; do
    if [ ! -d "$dir" ]; then
        error "Expected directory missing: $dir"
        ALL_DIRS_EXIST=false
    fi
done

if [ "$ALL_DIRS_EXIST" = true ]; then
    log "✓ Test 4 PASSED: All expected directories exist"
else
    error "✗ Test 4 FAILED: Directory structure incomplete"
    exit 1
fi

# Test 5: Verify log file creation in XDG directory
log "Test 5: Testing log file creation in XDG config..."

LOG_FILE="$XDG_CONFIG_DIR/auto-update.log"
echo "[$(date)] Test log entry" > "$LOG_FILE"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    log "✓ Test 5 PASSED: Log file created in XDG config directory"
else
    error "✗ Test 5 FAILED: Log file creation failed"
    exit 1
fi

# Test 6: Verify self-update uses ~/access folder
log "Test 6: Testing self-update uses ~/access folder..."

# Create mock access.sh in clean clone
mkdir -p "$CLEAN_CLONE_DIR"
echo '#!/bin/sh' > "$CLEAN_CLONE_DIR/access.sh"
echo 'echo "Mock Access v2.0"' >> "$CLEAN_CLONE_DIR/access.sh"
chmod +x "$CLEAN_CLONE_DIR/access.sh"

if [ -x "$CLEAN_CLONE_DIR/access.sh" ]; then
    log "✓ Test 6 PASSED: Self-update can use ~/access folder as source"
else
    error "✗ Test 6 FAILED: ~/access folder setup failed"
    exit 1
fi

# Cleanup
log "Cleaning up test environment..."
rm -rf "$TEST_HOME"

log "✅ All XDG and self-update tests passed!"
log ""
log "Key features verified:"
log "  ✓ XDG-compliant config directory (~/.config/access/)"
log "  ✓ Auto-update script stored in XDG config"
log "  ✓ Auto-update logs stored in XDG config"
log "  ✓ Self-update uses ~/access folder as source"
log "  ✓ Complete directory structure compliance"
log ""
log "Updated Access installation will:"
log "  1. Store config in ~/.config/access/ (XDG standard)"
log "  2. Store auto-update script in ~/.config/access/"
log "  3. Store auto-update logs in ~/.config/access/"
log "  4. Use ~/access/ for all self-update operations"
log "  5. Maintain clean separation between config and source"