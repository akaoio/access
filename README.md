# @akaoio/access

Pure POSIX shell implementation for automatic IP synchronization with multiple DNS providers - The eternal foundation layer for network infrastructure

> While languages come and go, shell is eternal.

**Version**: 0.0.3  
**License**: MIT  
**Repository**: https://github.com/akaoio/access

## Overview

Access is designed as eternal infrastructure with multiple layers providing automatic DNS IP synchronization that works forever. Version 0.0.3 introduces modular provider system with color logging and enhanced module organization.

## Core Principles


### Pure Shell Promise
NEVER requires Node.js, Python, Go, Rust, NPM, pip, cargo, compilation, transpilation, or build steps. Only POSIX shell and provider CLIs.


### Zero Dependencies Philosophy
Uses only standard POSIX utilities (sh, curl/wget, dig/nslookup, cron) and provider-specific CLIs


### Single Responsibility
Does ONE thing extremely well - IP synchronization with DNS providers. No feature creep allowed.


### Eternal Infrastructure
Sits below all other infrastructure - when everything else fails, Access survives


## Features

- **Modular Provider Architecture**: Hot-swappable provider modules in providers/ directory with standardized interfaces
- **Color-Coded Logging**: Enhanced visual feedback with color-coded status messages and error reporting
- **Dynamic Module Loading**: Runtime loading of provider and utility modules without restart
- **Multi-Provider Support**: Works with major cloud providers and traditional DNS services
- **Automatic IP Detection**: Reliable multi-tier IP detection with DNS and HTTP fallbacks
- **Provider Discovery**: Auto-discover available providers at runtime from modular directory structure
- **XDG Compliance**: Follows XDG Base Directory specification for configuration
- **Service Integration**: Native systemd service and cron job support
- **Auto-Update Capability**: Self-updating mechanism for the Access tool itself
- **Private IP Filtering**: Automatically filters RFC 1918 private IP ranges
- **Secure Configuration**: Encrypted credential storage with proper file permissions

## Installation

### Quick Start

```bash
# Clone and setup
git clone https://github.com/akaoio/access.git
cd access
chmod +x access.sh

# Run directly
./access.sh ip

# Or install globally
sudo cp access.sh /usr/local/bin/access
access help
```

### System Integration

```bash
# Setup as systemd service
./access.sh daemon --setup

# Or add to crontab
crontab -e
# Add: */5 * * * * /usr/local/bin/access update
```

## Usage

### Basic Commands

```bash
# Check current IP
access ip

# Update DNS with current IP
access update

# Configure provider
access config cloudflare
access config set domain example.com
access config set host @

# Run daemon
access daemon

# Check all providers
access providers

# Check provider health
access health
```

## Provider Support

### Cloud Providers
#### AWS Route53
- **Description**: Amazon Web Services DNS
- **Requirement**: AWS CLI
- **Status**: ✅ Supported

#### Google Cloud DNS
- **Description**: Google Cloud Platform DNS
- **Requirement**: gcloud CLI
- **Status**: ✅ Supported

#### Azure DNS
- **Description**: Microsoft Azure DNS Service
- **Requirement**: Azure CLI
- **Status**: ✅ Supported


### Traditional Providers
#### Cloudflare
- **Description**: Leading CDN and DNS provider
- **Requirement**: API credentials  
- **Status**: ✅ Supported

#### GoDaddy
- **Description**: Popular domain registrar
- **Requirement**: API credentials  
- **Status**: ✅ Supported

#### DigitalOcean
- **Description**: Developer-friendly cloud platform
- **Requirement**: API token  
- **Status**: ✅ Supported


## IP Detection Methods

### DNS Resolution (Fastest)
OpenDNS resolver queries using dig or nslookup
- **Response Time**: Sub-second

### HTTP Services (Fallback)
- checkip.amazonaws.com (AWS infrastructure)
- ipv4.icanhazip.com (reliable service)
- ifconfig.me (fallback option)

### Validation
Filters private/reserved IP ranges (RFC 1918) and validates IP format

## Security

### Credential Security
- All credentials stored locally in ~/.config/access/config.json
- File permissions set to 600 (user read/write only)
- No credentials transmitted in URLs or logs
- HTTPS required for all API communication

### Network Security
- Private IP ranges filtered (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- DNS queries use secure resolvers
- API rate limiting respected
- Timeout limits on all network calls

### System Security
- No root privileges required for normal operation
- Systemd service runs as dedicated user
- Log rotation configured
- No temporary files in world-readable locations

## Why Access?

Access represents the foundational layer of network infrastructure - it&#x27;s the system that ensures your services remain accessible even when everything else fails. By keeping it pure POSIX shell, we guarantee it will work on any Unix-like system, forever.

**One job. Done perfectly. Forever.**

### Benefits
- Zero dependencies means zero dependency hell
- POSIX compliance ensures universal compatibility
- Simple design ensures reliability
- Shell-based means it works when nothing else does
- Eternal infrastructure that outlasts technology trends

## Architecture

### Core Engine (access.sh)
Main orchestration engine with color logging and enhanced error handling
- **Responsibility**: Command processing, provider coordination, and system integration

### Provider Modules (providers/)
Modular provider implementations for different DNS services
- **Responsibility**: DNS provider-specific operations with standardized interfaces

### Shared Modules (modules/)
Common functionality shared across all providers
- **Responsibility**: Utility functions, IP detection, and configuration management


### System Layers

#### USER INTERFACE
Simple command interface with color-coded output for all operations

**Commands**: access ip, access update, access config, access providers

**Capability**: 

#### PROVIDER SCANNING
Auto-agnostic runtime provider detection with modular loading


**Capability**: Discovers available providers dynamically from providers/ directory

#### PROVIDER ABSTRACTION
Unified interface for all DNS providers with modular architecture


**Capability**: Consistent API across different provider types with hot-swappable modules

#### IP DETECTION
Multi-tier detection with DNS resolution and HTTP fallback chain


**Capability**: Reliable IP detection even in degraded conditions with color status feedback

#### POSIX SHELL CORE
Pure /bin/sh with no external dependencies and enhanced modularity


**Capability**: Runs on any Unix-like system forever with hot-loadable modules


---

*Access is the eternal foundation - while applications come and go, Access ensures your DNS always points home.*

*Version: 0.0.3 | License: MIT | Author: AKAO Team*
