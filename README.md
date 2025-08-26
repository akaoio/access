# Access - Dynamic DNS IP Synchronization (v0.0.1)

Pure POSIX shell implementation for automatic IP synchronization with multiple DNS providers.
Early release with auto-agnostic provider discovery system.

## Philosophy

While languages come and go, shell is eternal. Access is written in pure POSIX shell to ensure it survives forever, providing the most fundamental layer of connectivity - keeping your DNS synchronized with your dynamic IP.

## Features

- **Pure Shell**: Zero dependencies beyond standard POSIX utilities
- **Auto-Agnostic Discovery**: Providers are discovered at runtime, not hardcoded
- **Big Tech Provider Support**: AWS Route53, Google Cloud DNS, Azure DNS, Cloudflare, GoDaddy, DigitalOcean
- **Flexible Deployment**: Systemd service, cron job, or both
- **Auto-Update**: Optional self-updating capability
- **Reliable Detection**: Multiple IP detection methods (DNS & HTTP)
- **Simple Configuration**: One command setup per provider
- **Provider Health Checks**: Built-in provider validation and health monitoring
- **Single Responsibility**: Does one thing extremely well - IP synchronization

## Installation

### Default (Cron every 5 minutes)
```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh
```

### Systemd Service
```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh -s -- --systemd
```

### Custom Cron Interval
```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh -s -- --interval=10
```

### Both Service and Cron with Auto-Update
```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh -s -- --systemd --cron --auto-update
```

## Quick Start

### 1. Configure Your DNS Provider

#### GoDaddy
```bash
access config godaddy \
  --key=YOUR_API_KEY \
  --secret=YOUR_API_SECRET \
  --domain=example.com \
  --host=@
```

#### Cloudflare
```bash
access config cloudflare \
  --email=your@email.com \
  --api-key=YOUR_API_KEY \
  --zone-id=YOUR_ZONE_ID \
  --domain=example.com \
  --host=@
```

#### DigitalOcean
```bash
access config digitalocean \
  --token=YOUR_API_TOKEN \
  --domain=example.com \
  --host=@
```

#### Azure DNS
```bash
access config azure \
  --subscription-id=YOUR_SUBSCRIPTION_ID \
  --resource-group=YOUR_RESOURCE_GROUP \
  --tenant-id=YOUR_TENANT_ID \
  --client-id=YOUR_CLIENT_ID \
  --client-secret=YOUR_CLIENT_SECRET \
  --domain=example.com \
  --host=@
```

#### Google Cloud DNS
```bash
access config gcloud \
  --project-id=YOUR_PROJECT_ID \
  --zone-name=YOUR_ZONE_NAME \
  --service-account-key=YOUR_BASE64_KEY \
  --domain=example.com \
  --host=@
```

#### AWS Route53
```bash
access config route53 \
  --zone-id=YOUR_HOSTED_ZONE_ID \
  --access-key=YOUR_ACCESS_KEY \
  --secret-key=YOUR_SECRET_KEY \
  --domain=example.com \
  --host=@
```

### 2. Test Your Setup

```bash
# Check IP detection
access ip

# Test DNS update
access update
```

### 3. Automatic Updates

#### Cron Job (Default)
```bash
# View cron job
crontab -l

# Remove cron job
crontab -l | grep -v access | crontab -
```

#### Systemd Service
```bash
# Start service
sudo systemctl start access

# Enable on boot
sudo systemctl enable access

# View logs
sudo journalctl -u access -f
```

#### Auto-Update Feature
If installed with `--auto-update`, Access will automatically update itself weekly.
You can also manually update:
```bash
access auto-update
```

## Manual Usage

```bash
# Core Commands
access ip              # Detect and display public IP
access update          # Update DNS with current IP
access daemon          # Run continuous updates (foreground)
access config          # Configure DNS provider
access auto-update     # Check and install updates
access version         # Show version
access help            # Show help

# Provider Discovery (v0.0.1+)
access discover        # Auto-discover all available providers
access providers       # List providers with descriptions
access capabilities    # Show what a provider can do
access suggest         # Suggest provider for your domain
access health          # Check health of all providers
```

## Configuration

Configuration is stored in `~/.access/config.json`

Environment variables can override config:
- `ACCESS_PROVIDER` - DNS provider
- `ACCESS_DOMAIN` - Domain to update
- `ACCESS_HOST` - Host record (@ for root)
- `ACCESS_INTERVAL` - Update interval in seconds (daemon mode)
- `AUTO_UPDATE` - Enable auto-updates on 'update' command (true/false)

Provider-specific environment variables:
- GoDaddy: `GODADDY_KEY`, `GODADDY_SECRET`
- Cloudflare: `CLOUDFLARE_EMAIL`, `CLOUDFLARE_API_KEY`, `CLOUDFLARE_ZONE_ID`
- DigitalOcean: `DO_API_TOKEN`
- Azure: `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`
- Google Cloud: `GCLOUD_PROJECT_ID`, `GCLOUD_ZONE_NAME`, `GCLOUD_SERVICE_ACCOUNT_KEY`
- Route53: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ROUTE53_ZONE_ID`

## IP Detection Methods

Access uses multiple fallback methods to detect your public IP:

1. **DNS Resolution** (fastest)
   - OpenDNS resolver
   - Uses `dig` or `nslookup`

2. **HTTP Services** (fallback)
   - checkip.amazonaws.com
   - ipv4.icanhazip.com
   - ifconfig.me

## Provider Support

### Major Cloud Providers (Big Tech)
- ✅ **AWS Route53** - Amazon Web Services DNS (requires AWS CLI)
- ✅ **Google Cloud DNS** - Google Cloud Platform (requires gcloud CLI)
- ✅ **Azure DNS** - Microsoft Azure DNS Service
- ✅ **Cloudflare** - Leading CDN and DNS provider

### Traditional Providers
- ✅ **GoDaddy** - Popular domain registrar
- ✅ **DigitalOcean** - Developer-friendly cloud platform

## Requirements

- POSIX-compliant shell (`/bin/sh`)
- `curl` or `wget`
- `dig` or `nslookup` (optional, for DNS detection)
- `cron` (for automatic updates)
- `aws` CLI (only for Route53 provider)
- `gcloud` CLI (only for Google Cloud DNS provider)

## Security

- Credentials stored locally in `~/.access/config.json`
- All API calls use HTTPS
- Private/reserved IPs are filtered
- Detailed logging to `~/.access/access.log`

## Pure Shell Promise

This project will NEVER require:
- Node.js, Python, Go, Rust, or any runtime
- NPM, pip, cargo, or any package manager
- Compilation, transpilation, or build steps
- Anything beyond POSIX shell (except provider-specific CLIs)

## Why Access?

Access sits below all other infrastructure. When databases fail, when applications crash - Access survives. It's the layer that ensures your DNS always points to the right IP, no matter what.

**One job. Done perfectly. Forever.**

## License

MIT

## Contributing

Pull requests welcome! Please ensure:
- POSIX shell compatibility
- No external dependencies beyond standard utilities
- Provider implementations follow existing patterns
- Single responsibility principle - IP sync only