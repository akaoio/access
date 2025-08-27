# CLAUDE.md - @akaoio/access

This file provides guidance to Claude Code (claude.ai/code) when working with the @akaoio/access Dynamic DNS IP Synchronization system.

## Project Overview

**@akaoio/access** - Pure POSIX shell implementation for automatic IP synchronization with multiple DNS providers. Access is the foundational network access layer that sits below all other infrastructure in the AKAO ecosystem.

**Version**: 0.0.1 (Early Release)
**License**: MIT  
**Repository**: https://github.com/akaoio/access
**Philosophy**: "While languages come and go, shell is eternal."

## Core Development Principles

### Pure Shell Promise

This project will NEVER require:
- Node.js, Python, Go, Rust, or any runtime
- NPM, pip, cargo, or any package manager  
- Compilation, transpilation, or build steps
- Anything beyond POSIX shell (except provider-specific CLIs)

**Critical**: true

### Zero Dependencies Philosophy

Access uses only standard POSIX utilities and external CLIs for specific providers:
- Core functionality: `sh`, `curl`/`wget`, `dig`/`nslookup`, `cron`
- Provider-specific: `aws` CLI (Route53), `gcloud` CLI (Google DNS)

**Critical**: true

### Single Responsibility

Access does ONE thing extremely well - IP synchronization with DNS providers.
- No feature creep allowed
- No additional functionality beyond DNS sync
- Keep it simple, reliable, eternal

**Critical**: true

### Eternal Infrastructure

Access sits below all other infrastructure - when everything else fails, Access survives.
This is the foundational layer that ensures DNS always points to the right IP.

**Critical**: true

## Architecture Overview

### System Design

Access is designed as eternal infrastructure with multiple layers:

```
┌─────────────────────────────────────────┐
│            USER INTERFACE               │
│  access ip | access update | access config │
├─────────────────────────────────────────┤
│         PROVIDER DISCOVERY              │
│  Auto-agnostic runtime provider detection │
├─────────────────────────────────────────┤
│         PROVIDER ABSTRACTION            │
│  Unified interface for all DNS providers │
├─────────────────────────────────────────┤
│           IP DETECTION                  │
│   DNS resolution + HTTP fallback chain  │
├─────────────────────────────────────────┤
│         POSIX SHELL CORE                │
│    Pure /bin/sh - no external dependencies │
└─────────────────────────────────────────┘
```

### Core Components

**Main Script** (`access`)
- Entry point and command router
- Handles all user commands and argument parsing
- Coordinates between detection, providers, and configuration

**IP Detection Engine**
- Multiple fallback methods for reliability
- DNS resolution (fastest): OpenDNS resolver
- HTTP services (fallback): AWS, icanhazip, ifconfig.me
- Private/reserved IP filtering

**Provider System**
- Auto-agnostic discovery: Providers discovered at runtime
- Big Tech support: AWS Route53, Google Cloud DNS, Azure DNS
- Traditional providers: GoDaddy, Cloudflare, DigitalOcean
- Unified configuration interface

**Configuration Management**
- JSON-based configuration in `~/.config/access/config.json` (XDG-compliant)
- Environment variable overrides
- Secure credential storage (HTTPS only)

**Automation Layer**
- Systemd service integration
- Cron job management
- Auto-update capability
- Health monitoring

## Supported Providers

### Major Cloud Providers (Big Tech)
- ✅ **AWS Route53** - Amazon Web Services DNS (requires AWS CLI)
- ✅ **Google Cloud DNS** - Google Cloud Platform (requires gcloud CLI)  
- ✅ **Azure DNS** - Microsoft Azure DNS Service
- ✅ **Cloudflare** - Leading CDN and DNS provider

### Traditional Providers
- ✅ **GoDaddy** - Popular domain registrar
- ✅ **DigitalOcean** - Developer-friendly cloud platform

## Command Interface

### Core Commands
```bash
access ip              # Detect and display public IP
access update          # Update DNS with current IP
access daemon          # Run continuous updates (foreground)
access config          # Configure DNS provider
access auto-update     # Check and install updates
access version         # Show version
access help            # Show help
```

### Provider Discovery (v0.0.1+)
```bash
access discover        # Auto-discover all available providers
access providers       # List providers with descriptions
access capabilities    # Show what a provider can do
access suggest         # Suggest provider for your domain
access health          # Check health of all providers
```

## Configuration System

### Storage Location
- Primary config: `~/.config/access/config.json`
- Logs: `~/.local/share/access/access.log`
- All data stored locally (no cloud dependencies)

### Environment Variable Support
Core variables:
- `ACCESS_PROVIDER` - DNS provider
- `ACCESS_DOMAIN` - Domain to update
- `ACCESS_HOST` - Host record (@ for root)
- `ACCESS_INTERVAL` - Update interval in seconds
- `AUTO_UPDATE` - Enable auto-updates (true/false)

Provider-specific variables:
- GoDaddy: `GODADDY_KEY`, `GODADDY_SECRET`
- Cloudflare: `CLOUDFLARE_EMAIL`, `CLOUDFLARE_API_KEY`, `CLOUDFLARE_ZONE_ID`
- DigitalOcean: `DO_API_TOKEN`
- Azure: `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`
- Google Cloud: `GCLOUD_PROJECT_ID`, `GCLOUD_ZONE_NAME`, `GCLOUD_SERVICE_ACCOUNT_KEY`
- Route53: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ROUTE53_ZONE_ID`

## Installation Methods

### Default Installation (Cron every 5 minutes)
```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh
```

### Systemd Service
```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh -s -- --systemd
```

### Custom Configuration
```bash
# Custom interval
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh -s -- --interval=10

# Both service and cron with auto-update
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh -s -- --systemd --cron --auto-update
```

## IP Detection Methods

Access uses a reliable multi-tier detection system:

### Tier 1: DNS Resolution (Fastest)
- OpenDNS resolver queries
- Uses `dig` or `nslookup` (POSIX compliant)
- Sub-second response times

### Tier 2: HTTP Services (Fallback)
- checkip.amazonaws.com (AWS infrastructure)
- ipv4.icanhazip.com (reliable service)
- ifconfig.me (fallback option)

### IP Validation
- Filters private/reserved IP ranges (RFC 1918)
- Validates IP format before DNS updates
- Handles IPv4 (IPv6 support planned)

## Provider Configuration Examples

### GoDaddy Configuration
```bash
access config godaddy \
  --key=YOUR_API_KEY \
  --secret=YOUR_API_SECRET \
  --domain=example.com \
  --host=@
```

### Cloudflare Configuration
```bash
access config cloudflare \
  --email=your@email.com \
  --api-key=YOUR_API_KEY \
  --zone-id=YOUR_ZONE_ID \
  --domain=example.com \
  --host=@
```

### AWS Route53 Configuration
```bash
access config route53 \
  --zone-id=YOUR_HOSTED_ZONE_ID \
  --access-key=YOUR_ACCESS_KEY \
  --secret-key=YOUR_SECRET_KEY \
  --domain=example.com \
  --host=@
```

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
- All API calls use HTTPS
- No credentials in logs or error messages
- Validate all user input
- Use secure temp file creation

### Code Organization

```
access                 # Main executable script
├── Core Functions
│   ├── detect_ip()       # IP detection logic
│   ├── update_dns()      # DNS update orchestration
│   └── load_config()     # Configuration management
├── Provider Functions
│   ├── godaddy_update()  # GoDaddy API integration
│   ├── cloudflare_update() # Cloudflare API integration
│   └── route53_update()  # AWS Route53 integration
└── Utility Functions
    ├── log()            # Logging functionality
    ├── validate_ip()    # IP validation
    └── check_deps()     # Dependency verification
```

### Testing Requirements

**Manual Testing**
- Test on multiple Linux distributions
- Verify provider integrations with real accounts
- Test failure scenarios and recovery
- Validate cron and systemd integration

**Integration Testing**
```bash
# Test IP detection
access ip

# Test configuration
access config provider --key=test --domain=test.com

# Test DNS update (dry run)
ACCESS_DRY_RUN=true access update

# Test daemon mode (short interval)
ACCESS_INTERVAL=10 access daemon
```

## Automation and Deployment

### Systemd Service Management
```bash
# Service operations
sudo systemctl start access
sudo systemctl enable access
sudo systemctl status access

# View logs
sudo journalctl -u access -f
sudo journalctl -u access --since today
```

### Cron Job Management
```bash
# View current cron job
crontab -l | grep access

# Remove cron job
crontab -l | grep -v access | crontab -

# Manual cron entry (every 5 minutes)
*/5 * * * * /usr/local/bin/access update >/dev/null 2>&1
```

### Auto-Update System
```bash
# Manual update check
access auto-update

# Enable auto-update on install
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh -s -- --auto-update

# Auto-update runs weekly when enabled
```

## Security Considerations

### Credential Security
- All credentials stored locally in `~/.config/access/config.json`
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

## Troubleshooting Guide

### Common Issues

**IP Detection Failures**
```bash
# Debug IP detection
access ip --debug

# Check network connectivity
curl -s checkip.amazonaws.com
dig @resolver1.opendns.com myip.opendns.com +short
```

**DNS Update Failures**
```bash
# Check configuration
cat ~/.config/access/config.json

# Test provider connectivity
access health

# Check logs
tail -f ~/.local/share/access/access.log
```

**Service Issues**
```bash
# Check service status
sudo systemctl status access

# Check service logs
sudo journalctl -u access --since "1 hour ago"

# Restart service
sudo systemctl restart access
```

## Notes for AI Assistants

When working with Access:

### Critical Guidelines
- **NEVER suggest non-POSIX shell features** (arrays, functions, etc.)
- **Always maintain POSIX compliance** - test with `/bin/sh`
- **Respect the Pure Shell Promise** - no additional dependencies
- **Focus on reliability over features** - this is infrastructure code
- **Maintain backwards compatibility** - this must work forever

### Development Best Practices
- **Start with IP detection testing** before provider work
- **Test with real DNS providers** when possible
- **Check multiple Linux distributions** (Ubuntu, Alpine, CentOS)
- **Validate all user input** and configuration
- **Use proper error handling** with meaningful messages

### Security Requirements
- **Never log credentials** or sensitive data
- **Always use HTTPS** for API calls
- **Validate IP addresses** before DNS updates
- **Set proper file permissions** on config files
- **Check for private IP ranges** in detection

### Common Patterns
```bash
# Standard error handling
command || {
    log "ERROR: Command failed"
    exit 1
}

# Configuration validation
[ -z "$API_KEY" ] && {
    echo "ERROR: API key not configured"
    exit 1
}

# Safe temp file creation
TEMP_FILE=$(mktemp) || exit 1
trap 'rm -f "$TEMP_FILE"' EXIT
```

## Why Access Matters

Access represents the foundational layer of network infrastructure - it's the system that ensures your services remain accessible even when everything else fails. By keeping it pure POSIX shell, we guarantee it will work on any Unix-like system, forever.

**One job. Done perfectly. Forever.**

---

*Access is the eternal foundation - while applications come and go, Access ensures your DNS always points home.*

*Version: 0.0.1 | License: MIT | Author: AKAO Team*