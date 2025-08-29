# CLAUDE.md - 

This file provides guidance to Claude Code (claude.ai/code) when working with the  codebase.

## Project Overview

**** - 

**Version**:   
**License**:   
**Author**:   
**Repository**:   
**Philosophy**: ""

## Core Development Principles



## Architecture Overview

### System Design



### Core Components



## Features



## Command Interface

### Core Commands

```bash

```

### Detailed Command Reference



## Environment Variables



## Development Guidelines

### Shell Script Standards

**POSIX Compliance**
- Use `/bin/sh` (not bash-specific features)
- Avoid bashisms and GNU-specific extensions
- Test on multiple shells (dash, ash, bash)

**Error Handling**
- Always check exit codes: `command || handle_error`
- Use proper error messages with context
- Fail fast and clearly on configuration errors

**Security Practices**
- Validate all user input
- Use secure temp file creation
- Never expose sensitive data in logs
- Proper file permissions (600 for configs)

### Code Organization

```
manager.sh              # Main entry point
├── Core Functions
│   ├── stacker_init()      # Framework initialization
│   ├── stacker_config()    # Configuration management
│   └── stacker_error()     # Error handling
├── Module Loading
│   ├── load_module()       # Dynamic module loading
│   └── verify_module()     # Module verification
└── Utility Functions
    ├── log()              # Logging functionality
    ├── validate_posix()   # POSIX compliance check
    └── check_deps()       # Dependency verification
```

### Module Development

Each module follows this pattern:

```bash
#!/bin/sh
# Module: module-name
# Description: Brief description
# Dependencies: none (or list them)

# Module initialization
module_init() {
    # Initialization code
}

# Module functions
module_function() {
    # Function implementation
}

# Module cleanup
module_cleanup() {
    # Cleanup code
}

# Export module interface
STACKER_MODULE_NAME="module-name"
STACKER_MODULE_VERSION="1.0.0"
```

### Testing Requirements

**Manual Testing**
- Test on multiple shells (sh, dash, ash, bash)
- Verify on different Unix-like systems
- Test failure scenarios and recovery
- Validate all command options

**Test Framework**
```bash
# Run all tests
./tests/run-all.sh

# Run specific test
./tests/test-core.sh

# Test with specific shell
SHELL=/bin/dash ./tests/run-all.sh
```

## Common Patterns

### Standard Error Handling
```bash
# Function with error handling
function_name() {
    command || {
        log "ERROR: Command failed: $*"
        return 1
    }
}
```

### Configuration Validation
```bash
# Validate required configuration
validate_config() {
    [ -z "$CONFIG_VALUE" ] && {
        echo "ERROR: CONFIG_VALUE not set"
        exit 1
    }
}
```

### Safe Temp File Creation
```bash
# Create temporary file safely
TEMP_FILE=$(mktemp) || exit 1
trap 'rm -f "$TEMP_FILE"' EXIT
```

### Module Loading
```bash
# Load module with verification
load_module "module-name" || {
    log "ERROR: Failed to load module: module-name"
    exit 1
}
```

## Use Cases



## Security Considerations

### Framework Security
- All modules verified before loading
- Configuration files with restricted permissions (600)
- No execution of untrusted code
- Input validation at all entry points

### Deployment Security
- Secure installation process
- Proper service user creation
- Limited privileges for service execution
- Audit logging for critical operations

## Troubleshooting Guide

### Common Issues

**Module Loading Failures**
```bash
# Debug module loading
STACKER_DEBUG=true manager init

# Check module path
echo $STACKER_MODULE_PATH

# Verify module syntax
sh -n module-name.sh
```

**Configuration Issues**
```bash
# Check configuration
manager config list

# Validate configuration file
manager config validate

# Reset configuration
rm -rf ~/.config/manager
manager init
```

**Service Issues**
```bash
# Check service status
manager service status

# View service logs
journalctl -u manager -f

# Restart service
manager service restart
```

## Notes for AI Assistants

When working with Manager:

### Critical Guidelines
- **ALWAYS maintain POSIX compliance** - test with `/bin/sh`
- **NEVER introduce dependencies** - pure shell only
- **Follow the module pattern** - consistency is key
- **Test on multiple shells** - dash, ash, sh, bash
- **Respect the framework philosophy** - universal patterns

### Development Best Practices
- **Start with the core module** - understand the foundation
- **Use existing patterns** - don't reinvent the wheel
- **Test error conditions** - robust error handling
- **Document module interfaces** - clear contracts
- **Validate all inputs** - security first

### Common Mistakes to Avoid
- Using bash-specific features (arrays, [[ ]], etc.)
- Assuming GNU coreutils extensions
- Hardcoding paths instead of using variables
- Forgetting to check exit codes
- Not testing on minimal systems

### Framework Extensions
When extending Stacker:
1. Create new module following the pattern
2. Add module to the module registry
3. Update configuration schema if needed
4. Add tests for new functionality
5. Document in module header

## 



### Benefits


---

*Stacker is the foundation - bringing order to chaos through universal shell patterns.*

*Version:  | License:  | Author: *