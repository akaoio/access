# Access Eternal

> **Minimal POSIX Dynamic DNS** - When everything fails, Access survives

**Access** is a bulletproof dynamic DNS updater that maintains network accessibility through IP changes. Built for reliability with zero external dependencies beyond standard POSIX tools.

## 🚀 Quick Start

### One-Line Installation

```bash
curl -s https://raw.githubusercontent.com/akaoio/access/main/install.sh | sudo sh
```

That's it! The installer will:
1. Install git if needed
2. Clone and install Access to system directories
3. Ask which DNS provider you use (GoDaddy or Cloudflare) and prompt for its credentials
4. Set up triple monitoring: daemon (real-time) + timers + cron backup
5. Start monitoring immediately

### Manual Installation

```bash
git clone https://github.com/akaoio/access
cd access
sudo ./install.sh
```

## 🛠️ Commands

After installation:

```bash
access ip        # Show current IPv4 and IPv6 addresses
access sync      # Sync DNS records with current IP
access status    # Show system status and monitoring info
access update    # Update Access to latest version
access uninstall # Remove Access from system
access help      # Show help message
```

## 📊 Architecture

**Triple Redundancy System:**
- **Primary**: Real-time daemon with `ip monitor addr` (instant detection)
- **Secondary**: Systemd timers (5min sync + weekly update)
- **Backup**: Cron jobs (fallback if systemd fails)

**System Locations:**
- **Config**: `/etc/access/config.env`
- **Binary**: `/usr/local/bin/access`
- **Library**: `/usr/local/lib/access/`
- **State**: `/var/lib/access/`
- **Logs**: `/var/log/access/`

## 🔍 Monitoring

**View logs:**
```bash
sudo tail -f /var/log/access/access.log   # Normal operation
sudo tail -f /var/log/access/error.log    # Errors only
```

**Check status:**
```bash
access status                              # Access status
sudo systemctl status access              # Systemd service
sudo systemctl list-timers access-*       # Systemd timers
```

## 📋 Requirements

- **Shell**: POSIX `/bin/sh`
- **Commands**: `curl`, `ip`, `git`
- **Privileges**: Root (for system installation)
- **DNS Provider**: GoDaddy or Cloudflare

## 🗂️ Configuration

During installation, you'll configure:
- **Provider** (`godaddy` or `cloudflare`)
- **Domain** (e.g., `example.com`)
- **Host** (e.g., `server1`)

Then, depending on the provider:

**GoDaddy**
- **GoDaddy API Key**
- **GoDaddy Secret**

Get API credentials: https://developer.godaddy.com/

**Cloudflare**
- **Cloudflare API Token** — create one at https://dash.cloudflare.com/profile/api-tokens using the "Edit zone DNS" template, scoped to your zone. Add the **Zone → Zone → Read** permission as well so the installer can auto-resolve your Zone ID.
- **Cloudflare Zone ID** — auto-resolved from your domain during install; you'll be asked to paste it manually if resolution fails.

Config is stored in `/etc/access/config.env`. New fields (`PROVIDER`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`) are additive — existing GoDaddy configs without a `PROVIDER` line keep working unchanged (defaults to `godaddy`).

## 🔄 How It Works

1. **IP Detection**: Prioritizes stable IPv6 → temporary IPv6 → IPv4
2. **Change Detection**: Real-time monitoring with `ip monitor addr`
3. **DNS Update**: Updates the configured provider's DNS via API (A/AAAA records). GoDaddy updates the record directly by name; Cloudflare looks up the record ID first, then patches it (creating it if it doesn't exist yet).
4. **Deduplication**: Only updates when IP actually changes
5. **Rate Limiting**: Prevents redundant updates (2min cooldown)

## 🛡️ Features

- **100% POSIX Compatible** - Works on Linux, BSD, macOS, Solaris
- **Zero Dependencies** - Only uses standard system tools
- **Modular Architecture** - Clean, maintainable code
- **Multi-Provider DNS** - GoDaddy and Cloudflare, via a pluggable `module/provider/*.sh` interface (add a new provider by dropping in one file)
- **Triple Redundancy** - Multiple monitoring layers
- **Smart Logging** - Separate normal/error logs
- **Process Locking** - Prevents concurrent operations
- **Graceful Degradation** - Continues working if components fail
- **One-Command Operations** - Install, update, uninstall

## 📜 License

MIT License

## 🤝 Contributing

1. Keep it minimal and POSIX compliant
2. Test on multiple shells (`dash`, `ash`, `bash`)
3. Follow existing code patterns
4. Document any new dependencies

---

**Access Eternal** - Because network connectivity shouldn't be complicated.