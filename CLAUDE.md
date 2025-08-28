# CLAUDE.md - @akaoio/access

This file provides guidance to Claude Code (claude.ai/code) when working with the @akaoio/access codebase.

## Project Overview

**@akaoio/access** - Pure POSIX shell implementation for automatic IP synchronization with multiple DNS providers - The eternal foundation layer for network infrastructure

**Version**: 0.0.3  
**License**: MIT  
**Author**: AKAO Team  
**Repository**: https://github.com/akaoio/access  
**Philosophy**: "While languages come and go, shell is eternal."

## Core Development Principles

### Pure Shell Promise
NEVER requires Node.js, Python, Go, Rust, NPM, pip, cargo, compilation, transpilation, or build steps. Only POSIX shell and provider CLIs.
**Critical**: true

### Zero Dependencies Philosophy
Uses only standard POSIX utilities (sh, curl/wget, dig/nslookup, cron) and provider-specific CLIs
**Critical**: true

### Single Responsibility
Does ONE thing extremely well - IP synchronization with DNS providers. No feature creep allowed.
**Critical**: true

### Eternal Infrastructure
Sits below all other infrastructure - when everything else fails, Access survives
**Critical**: true


## Architecture Overview

### System Design

Access is designed as eternal infrastructure with multiple layers providing automatic DNS IP synchronization that works forever. Version 0.0.3 introduces modular provider system with color logging and enhanced module organization.

### Core Components

**Core Engine (access.sh)**
- Main orchestration engine with color logging and enhanced error handling
- Responsibility: Command processing, provider coordination, and system integration

**Provider Modules (providers/)**
- Modular provider implementations for different DNS services
- Responsibility: DNS provider-specific operations with standardized interfaces

**Shared Modules (modules/)**
- Common functionality shared across all providers
- Responsibility: Utility functions, IP detection, and configuration management


## Features

### Modular Provider Architecture
Hot-swappable provider modules in providers/ directory with standardized interfaces

### Color-Coded Logging
Enhanced visual feedback with color-coded status messages and error reporting

### Dynamic Module Loading
Runtime loading of provider and utility modules without restart

### Multi-Provider Support
Works with major cloud providers and traditional DNS services

### Automatic IP Detection
Reliable multi-tier IP detection with DNS and HTTP fallbacks

### Provider Discovery
Auto-discover available providers at runtime from modular directory structure

### XDG Compliance
Follows XDG Base Directory specification for configuration

### Service Integration
Native systemd service and cron job support

### Auto-Update Capability
Self-updating mechanism for the Access tool itself

### Private IP Filtering
Automatically filters RFC 1918 private IP ranges

### Secure Configuration
Encrypted credential storage with proper file permissions


## Command Interface

### Core Commands

```bash
access ip  # Detect and display public IP
access update  # Update DNS with current IP
access daemon  # Run continuous updates (foreground)
access config [provider] [options]  # Configure DNS provider
access auto-update  # Check and install updates
access discover  # Auto-discover available providers
access providers  # List providers with descriptions
access capabilities [provider]  # Show what a provider can do
access suggest [domain]  # Suggest provider for your domain
access health  # Check health of all providers
access version  # Show version
access help [command]  # Show help
```

### Detailed Command Reference

#### `ip` Command
**Purpose**: Detect and display public IP  
**Usage**: `access ip`


**Examples**:
```bash
access ip  # Show current public IP
access ip --debug  # Show IP with debug information
```

#### `update` Command
**Purpose**: Update DNS with current IP  
**Usage**: `access update`


**Examples**:
```bash
access update  # Update DNS records
ACCESS_DRY_RUN&#x3D;true access update  # Test update without making changes
```

#### `daemon` Command
**Purpose**: Run continuous updates (foreground)  
**Usage**: `access daemon`


**Examples**:
```bash
access daemon  # Run in foreground with default interval
ACCESS_INTERVAL&#x3D;10 access daemon  # Run with 10 second interval
```

#### `config` Command
**Purpose**: Configure DNS provider  
**Usage**: `access config [provider] [options]`


**Examples**:
```bash
access config godaddy --key&#x3D;KEY --secret&#x3D;SECRET  # Configure GoDaddy provider
access config cloudflare --email&#x3D;EMAIL --api-key&#x3D;KEY  # Configure Cloudflare provider
```

#### `auto-update` Command
**Purpose**: Check and install updates  
**Usage**: `access auto-update`


**Examples**:
```bash
access auto-update  # Check for and apply updates
```

#### `discover` Command
**Purpose**: Auto-discover available providers  
**Usage**: `access discover`


**Examples**:
```bash
access discover  # Scan for available DNS providers
```

#### `providers` Command
**Purpose**: List providers with descriptions  
**Usage**: `access providers`


**Examples**:
```bash
access providers  # Show all supported providers
```

#### `capabilities` Command
**Purpose**: Show what a provider can do  
**Usage**: `access capabilities [provider]`


**Examples**:
```bash
access capabilities godaddy  # Show GoDaddy capabilities
```

#### `suggest` Command
**Purpose**: Suggest provider for your domain  
**Usage**: `access suggest [domain]`


**Examples**:
```bash
access suggest example.com  # Get provider recommendation
```

#### `health` Command
**Purpose**: Check health of all providers  
**Usage**: `access health`


**Examples**:
```bash
access health  # Check provider connectivity
```

#### `version` Command
**Purpose**: Show version  
**Usage**: `access version`



#### `help` Command
**Purpose**: Show help  
**Usage**: `access help [command]`




## Environment Variables

### ACCESS_PROVIDER
- **Description**: DNS provider to use
- **Default**: ``

### ACCESS_DOMAIN
- **Description**: Domain to update
- **Default**: ``

### ACCESS_HOST
- **Description**: Host record (@ for root)
- **Default**: `@`

### ACCESS_INTERVAL
- **Description**: Update interval in seconds
- **Default**: `300`

### AUTO_UPDATE
- **Description**: Enable auto-updates
- **Default**: `false`

### ACCESS_DRY_RUN
- **Description**: Test mode without making changes
- **Default**: `false`


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
stacker.sh              # Main entry point
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
STACKER_DEBUG=true stacker init

# Check module path
echo $STACKER_MODULE_PATH

# Verify module syntax
sh -n module-name.sh
```

**Configuration Issues**
```bash
# Check configuration
stacker config list

# Validate configuration file
stacker config validate

# Reset configuration
rm -rf ~/.config/stacker
stacker init
```

**Service Issues**
```bash
# Check service status
stacker service status

# View service logs
journalctl -u stacker -f

# Restart service
stacker service restart
```

## Notes for AI Assistants

When working with Stacker:

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

*Version: 0.0.3 | License: MIT | Author: AKAO Team*