# Access

Pure shell network access layer. The eternal foundation that enables connectivity.

## Philosophy

While languages come and go, shell is eternal. Access is written in pure POSIX shell to ensure it survives forever, providing the most fundamental layer of network connectivity that makes everything else possible.

## What Access Does

- **Dynamic DNS Updates**: Syncs your home IP to DNS providers (GoDaddy, Cloudflare, Route53)
- **SSL/HTTPS Access**: Automatic SSL certificate management (self-signed + Let's Encrypt)
- **IPv6 Connectivity**: Enables direct access to home machines via IPv6
- **Network Detection**: Reliable IP detection through multiple methods
- **Zero Dependencies**: Pure shell, no runtime requirements

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | bash
```

## Usage

### DNS Management
```bash
# Update DNS with current IP
access update

# Check current IP
access ip

# Configure provider
access config godaddy --key=YOUR_KEY --secret=YOUR_SECRET --domain=example.com

# Run as daemon
access daemon
```

### SSL Certificate Management
```bash
# Generate self-signed certificate
access ssl generate example.com

# Setup Let's Encrypt certificate
access ssl letsencrypt example.com admin@example.com

# Renew certificates
access ssl renew

# Check certificate status
access ssl check

# Setup auto-renewal
access ssl auto-renew
```

## Why Access Exists

Access sits below all other infrastructure. When Air breaks, when databases fail, when applications crash - Access survives. It's the layer that ensures you can always reach your machine.

Access provides the three fundamental pillars of network connectivity:
1. **Discovery** - Your machine's IP is always synchronized to DNS
2. **Security** - SSL certificates ensure encrypted HTTPS access
3. **Persistence** - Pure shell ensures it works forever, on any system

## Provider Support

- ✅ GoDaddy
- 🚧 Cloudflare (coming soon)
- 🚧 AWS Route53 (coming soon)
- 🚧 Custom webhook (coming soon)

## Pure Shell Promise

This project will NEVER require:
- Node.js, Python, Go, Rust, or any runtime
- NPM, pip, cargo, or any package manager  
- Compilation, transpilation, or build steps
- Anything beyond POSIX shell

## License

MIT