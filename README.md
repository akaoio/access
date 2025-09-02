# Access Eternal

> "When everything fails, Access survives"

**Access** is a minimal, bulletproof dynamic DNS updater that maintains network accessibility through IP changes. Built for reliability with zero external dependencies beyond standard POSIX tools.

## ✨ Features

- **🔄 Real-time IP monitoring** using `ip monitor addr` - instant detection
- **🏗️ One-command installation** - `./access.sh install` does everything  
- **📁 100% XDG Base Directory compliant** - respects all XDG environment variables
- **🔧 100% POSIX shell compatible** - works on any Unix-like system
- **🚀 Dual monitoring architecture** - systemd service + cron backup
- **📝 Separate error logging** - operation logs and error logs split
- **⚡ Bulletproof redundancy** - systemd → cron → weekly auto-upgrade
- **🔒 Secure by design** - config files are `chmod 600`, no secrets in logs
- **🔄 Auto-upgrade system** - weekly updates with service restart
- **🛡️ Self-healing** - auto-restart on failures, boot persistence
- **📦 175 lines total** - minimal, auditable, enterprise-grade

## 🚀 Quick Start

### One Command Installation

```bash
curl -s https://raw.githubusercontent.com/akaoio/access/main/access.sh | bash -s install
```

Or download and run locally:

```bash
wget https://raw.githubusercontent.com/akaoio/access/main/access.sh
chmod +x access.sh
./access.sh install
```

That's it! The installer will:
1. Install binary to `~/.local/bin/access`
2. Prompt for your domain configuration (if first install)
3. Set up dual monitoring: systemd service (real-time) + cron backup (15min)
4. Install weekly auto-upgrade cron job
5. Start monitoring immediately with bulletproof redundancy

### Configuration

During installation, you'll be prompted for:

- **Domain** (default: `akao.io`)
- **Host** (default: `peer0`) 
- **GoDaddy API Key**
- **GoDaddy Secret**

This creates: `~/.config/access/config.env`

## 🛠️ Usage

After installation, Access runs automatically with dual monitoring:

- **Systemd service**: Real-time IP monitoring  
- **Cron backup**: DNS check every 15 minutes
- **Auto-upgrade**: Weekly updates every Sunday 3 AM

Manual commands:

```bash
access update     # Force DNS update now
access upgrade    # Upgrade to latest version (with auto-restart)
access uninstall  # Remove completely (service + all cron jobs)
```

## 📋 Requirements

- **Shell**: POSIX `/bin/sh`
- **Commands**: `curl`, `ip`, `systemctl` (optional)
- **DNS Provider**: GoDaddy API (extensible)

## 🗂️ File Locations

Access follows [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html):

```
~/.config/access/config.env          # Configuration
~/.local/bin/access                  # Executable  
~/.local/state/access/access.log     # Operation logs
~/.local/state/access/error.log      # Error logs (systemd stderr)
~/.local/state/access/last_ip        # IP deduplication cache
~/.config/systemd/user/access.service # Systemd service file
```

Custom locations via environment variables:
```bash
export XDG_CONFIG_HOME=/custom/config
export XDG_STATE_HOME=/custom/state  
export XDG_BIN_HOME=/custom/bin
```

## 🔍 Monitoring

**View logs:**
```bash
# Normal operation logs  
tail -f ~/.local/state/access/access.log

# Error logs (systemd stderr)
tail -f ~/.local/state/access/error.log
```

**Service status:**
```bash
systemctl --user status access.service  # Check systemd service
crontab -l | grep access                # Check cron backup jobs
```

**Monitoring details:**
- **Primary**: Systemd service with `ip monitor addr` (instant detection)
- **Backup**: Cron job every 15 minutes (safety net if systemd fails)
- **Auto-upgrade**: Weekly on Sunday 3 AM with automatic service restart
- **IP deduplication**: Prevents unnecessary DNS updates for same IP

## 🏗️ Dual Monitoring Architecture

```
                    ┌─────────────────────┐
                    │   IP Change Event   │ 
                    └─────────────────────┘
                              ↓
                    ┌─────────────────────┐
                    │    Dual Detection   │
                    └─────────────────────┘ 
                           ↙        ↘
              ┌─────────────────┐   ┌─────────────────┐
              │ Systemd Service │   │   Cron Backup   │
              │  (real-time)    │   │   (15 minutes)  │ 
              │ ip monitor addr │   │ access update   │
              └─────────────────┘   └─────────────────┘
                           ↘        ↙
                    ┌─────────────────────┐
                    │   update_dns()      │ ← Shared Logic
                    │ • IP deduplication  │
                    │ • Error resilience  │  
                    │ • GoDaddy API       │
                    └─────────────────────┘
                              ↓
                    ┌─────────────────────┐
                    │     DNS Updated     │
                    │   peer0.akao.io     │
                    └─────────────────────┘
```

## 🔧 Development

**Principles:**
- Pure POSIX shell for maximum compatibility
- XDG compliance for proper integration
- Zero external dependencies (beyond standard tools)
- Fail-fast with graceful degradation
- Self-contained single file

**Testing:**
```bash
# Test in isolated environment
export XDG_CONFIG_HOME=/tmp/test-config
export XDG_STATE_HOME=/tmp/test-state
./access.sh install
```

## 📜 License

MIT License - see repository for details.

## 🤝 Contributing

1. Keep it minimal and POSIX compliant
2. Follow XDG Base Directory Specification  
3. Maintain single-file architecture
4. Test on multiple shells (`dash`, `ash`, `bash`)
5. Document any new dependencies

---

**Access Eternal** - Because network connectivity shouldn't be complicated.