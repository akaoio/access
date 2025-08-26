# Access Test Suite

This directory contains the complete test suite for Access - the eternal network access layer.

## Test Categories

### 🧪 Battle Test Suite (.battle.cjs)
Real terminal testing using @akaoio/battle framework - tests actual command execution and output:

- `test-complete-coverage.battle.cjs` - Comprehensive functionality coverage
- `test-lifecycle-complete.battle.cjs` - Full installation/usage lifecycle 
- `test-visual-ux.battle.cjs` - Terminal UI and user experience testing

### 🔧 Development Test Scripts (.sh)
Shell scripts for testing specific components and features:

- `test-clean-clone-install.sh` - Clean clone installation mechanism
- `test-enhanced-installer.sh` - CLI flags and interactive TUI functionality
- `test-provider-fix.sh` - Provider dependency installation verification
- `test-xdg-selfupdate.sh` - XDG compliance and self-update mechanism

## Running Tests

### Battle Tests (Real Terminal Testing)
```bash
# Run comprehensive coverage test
node test/test-complete-coverage.battle.cjs

# Run lifecycle test
node test/test-lifecycle-complete.battle.cjs  

# Run visual UX test
node test/test-visual-ux.battle.cjs
```

### Development Tests
```bash
# Test installation mechanisms
./test/test-clean-clone-install.sh
./test/test-enhanced-installer.sh
./test/test-provider-fix.sh
./test/test-xdg-selfupdate.sh
```

## Test Framework

**Battle Framework**: Uses @akaoio/battle for real PTY testing
- No mocks - tests actual terminal interactions
- Real command execution and output verification
- Terminal UI testing for user experience

**Shell Testing**: Direct shell script validation
- Component isolation testing
- Feature verification scripts
- Integration validation

## Test Coverage

The test suite covers:
- ✅ Complete Access functionality (84/84 tests passing)
- ✅ All 6 DNS providers (GoDaddy, Cloudflare, DigitalOcean, Azure, Google Cloud, AWS Route53)
- ✅ Installation mechanisms (clean clone, provider dependencies)
- ✅ Self-update functionality (XDG compliance, git-based updates)
- ✅ CLI and interactive modes
- ✅ Error handling and edge cases
- ✅ Visual/UX terminal output
- ✅ Full installation lifecycle

This is a **PRODUCTION-GRADE TEST SUITE** ensuring Access works perfectly as the eternal foundation infrastructure layer.