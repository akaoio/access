# Access

Pure shell network access layer. The eternal foundation that enables connectivity.

## Philosophy

While languages come and go, shell is eternal. Access is written in pure POSIX shell to ensure it survives forever, providing the most fundamental layer of network connectivity that makes everything else possible.

## What Access Does

- **Dynamic DNS Updates**: Syncs your home IP to DNS providers (GoDaddy, Cloudflare, Route53)
- **IPv6 Connectivity**: Enables direct access to home machines via IPv6
- **Network Detection**: Reliable IP detection through multiple methods
- **Zero Dependencies**: Pure shell, no runtime requirements

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | bash
```

## Usage

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

## Why Access Exists

Access sits below all other infrastructure. When Air breaks, when databases fail, when applications crash - Access survives. It's the layer that ensures you can always reach your machine.

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