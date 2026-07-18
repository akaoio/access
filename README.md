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

- **OS**: Linux (relies on `iproute2`'s `ip monitor`, `flock` from util-linux, and systemd + cron for scheduling)
- **Shell**: POSIX `/bin/sh` (no bashisms; works under `dash`, `ash`, `bash`)
- **Commands**: `curl`, `ip`, `git`, `flock`
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

1. **IP Detection**: IPv4 via public lookup services (`ifconfig.me`, falling back to `icanhazip.com`); IPv6 from the interface's stable global address (temporary privacy addresses only as a fallback)
2. **Change Detection**: Real-time monitoring with `ip monitor addr`
3. **DNS Update**: Updates the configured provider's DNS via API (A/AAAA records). GoDaddy updates the record directly by name; Cloudflare looks up the record ID first, then patches it (creating it if it doesn't exist yet).
4. **Deduplication**: Only calls the provider API when the IP actually changed since the last successful sync (per-provider state in `/var/lib/access/`)
5. **Locking**: A `flock`-held lock file prevents daemon, timer and cron syncs from overlapping

## 🛡️ Features

- **POSIX Shell** - No bashisms; runs under `dash`, `ash`, `bash`
- **Minimal Dependencies** - Only `curl`, `git` and standard Linux tools (`iproute2`, `flock`)
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

### Adding a DNS Provider

All provider-specific code must stay inside a single `module/provider/<name>.sh` file - never in `sync.sh`, `install.sh`, or a shared config template. A provider module implements:

- `provider_validate()` - checks its own required config vars are set, printing `WARNING: ...` and `return 6` if not
- `provider_update_record TYPE VALUE` - updates the A/AAAA record (`TYPE` is `A`/`AAAA`, `VALUE` is the IP)
- `provider_install_prompt DOMAIN HOST` - install-time: prompt for credentials, resolve anything domain-dependent
- `provider_install_summary()` - install-time: print the values for the confirmation prompt
- `provider_write_config CONFIG_PATH` - install-time: append this provider's `KEY=VALUE` lines to the config file

`sync.sh` and `install.sh` only call these hooks by name (`$PROVIDER.sh` is sourced dynamically) - they must never reference a provider-specific variable or endpoint directly.

---

**Access Eternal** - Because network connectivity shouldn't be complicated.