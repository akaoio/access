# Access Eternal

> "When everything fails, Access survives"

**Access** is a minimal, bulletproof dynamic DNS updater that maintains network accessibility through IP changes. Built for reliability with zero external dependencies beyond standard POSIX tools.

## ✨ Features

- **🔄 Real-time IP monitoring** using `ip monitor addr` - no polling delays
- **🏗️ One-command installation** - `./access.sh install` does everything
- **📁 XDG Base Directory compliant** - respects `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME`, `$XDG_BIN_HOME`
- **🔧 POSIX shell compatible** - works on any Unix-like system
- **🚀 Systemd service integration** - auto-starts and self-manages
- **📝 Built-in logging** - tracks all IP changes and DNS updates
- **⚡ Graceful fallbacks** - systemd → cron → manual operation
- **🔒 Secure by design** - config files are `chmod 600`, no secrets in logs
- **📦 157 lines total** - minimal, auditable, maintainable

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
2. Prompt for your domain configuration
3. Set up real-time IP monitoring service
4. Start monitoring immediately

### Configuration

During installation, you'll be prompted for:

- **Domain** (default: `akao.io`)
- **Host** (default: `peer0`) 
- **GoDaddy API Key**
- **GoDaddy Secret**

This creates: `~/.config/access/config.env`

## 🛠️ Usage

After installation, Access runs automatically. Manual commands:

```bash
access update     # Force DNS update now
access upgrade    # Upgrade to latest version  
access uninstall  # Remove completely
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
~/.local/state/access/access.log     # Logs
~/.config/systemd/user/access.service # Service file
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
tail -f ~/.local/state/access/access.log
```

**Service status:**
```bash
systemctl --user status access.service
```

**Real-time monitoring:**
The service uses `ip monitor addr` to detect IP changes instantly, then updates DNS within seconds.

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────┐
│   IP Monitor    │ ─→ │ DNS Updater  │ ─→ │  GoDaddy    │
│ (ip monitor)    │    │ (curl API)   │    │    API      │
└─────────────────┘    └──────────────┘    └─────────────┘
         ↑                       ↑                  ↑
    Real-time IP            Parse & Format      Update DNS
    change detection        IP→DNS record       Record Live
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