# @akaoio/access

Pure POSIX shell implementation for automatic IP synchronization with multiple DNS providers - The eternal foundation layer for network infrastructure

> While languages come and go, shell is eternal.

**Version**: 0.0.3  
**License**: MIT  
**Repository**: https://github.com/akaoio/access

## 🎯 Educational Mission

Learn DNS synchronization patterns, POSIX shell mastery, and eternal infrastructure design

## 📖 What You'll Learn

Access is the eternal foundation - while applications come and go, Access ensures your DNS always points home.

Access is the perfect educational platform for learning eternal infrastructure design. This documentation teaches you not just HOW to use Access, but WHY it works and HOW to apply these patterns in your own projects.

## 🏗️ Core Architecture Principles (Learn by Example)


### Pure Shell Promise

**Technical Implementation**: NEVER requires Node.js, Python, Go, Rust, NPM, pip, cargo, compilation, transpilation, or build steps. Only POSIX shell and provider CLIs.

**What You'll Learn**: Master pure POSIX shell programming without modern dependencies


⭐ **Critical Concept**: This principle forms the foundation of all eternal infrastructure design.



### Zero Dependencies Philosophy

**Technical Implementation**: Uses only standard POSIX utilities (sh, curl/wget, dig/nslookup, cron) and provider-specific CLIs

**What You'll Learn**: Understand how to build robust systems with minimal dependencies


⭐ **Critical Concept**: This principle forms the foundation of all eternal infrastructure design.



### Single Responsibility

**Technical Implementation**: Does ONE thing extremely well - IP synchronization with DNS providers. No feature creep allowed.

**What You'll Learn**: Learn Unix philosophy of single-purpose tools done perfectly


⭐ **Critical Concept**: This principle forms the foundation of all eternal infrastructure design.



### Eternal Infrastructure

**Technical Implementation**: Sits below all other infrastructure - when everything fails, Access survives

**What You'll Learn**: Design systems that outlast technology trends and framework churn


⭐ **Critical Concept**: This principle forms the foundation of all eternal infrastructure design.




## 🎓 Architecture Deep Dive (Educational)

Access is designed as eternal infrastructure with multiple layers providing automatic DNS IP synchronization that works forever. Version 0.0.3 introduces modular provider system with color logging and enhanced module organization.

### Layer-by-Layer Learning


#### USER INTERFACE
- **How it Works**: Simple command interface with color-coded output for all operations
- **Key Capability**: 
- **Educational Value**: Design intuitive CLI interfaces that users can remember


**Command Examples**:

- `access ip`

- `access update`

- `access config`

- `access providers`




#### PROVIDER SCANNING
- **How it Works**: Auto-agnostic runtime provider detection with modular loading
- **Key Capability**: Discovers available providers dynamically from providers/ directory
- **Educational Value**: Implement plugin architectures in pure shell




#### PROVIDER ABSTRACTION
- **How it Works**: Unified interface for all DNS providers with modular architecture
- **Key Capability**: Consistent API across different provider types with hot-swappable modules
- **Educational Value**: Abstract different APIs behind common interfaces




#### IP DETECTION
- **How it Works**: Multi-tier detection with DNS resolution and HTTP fallback chain
- **Key Capability**: Reliable IP detection even in degraded conditions with color status feedback
- **Educational Value**: Build resilient systems with multiple fallback strategies




#### POSIX SHELL CORE
- **How it Works**: Pure /bin/sh with no external dependencies and enhanced modularity
- **Key Capability**: Runs on any Unix-like system forever with hot-loadable modules
- **Educational Value**: Write code that works everywhere and lasts forever





## 💡 Real-World Implementation Examples

### Multi-Tier IP Detection Pattern
```bash
# Educational example: Multi-tier IP detection
detect_ip() {
  # Tier 1: DNS resolution (fastest)
  ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
  
  # Tier 2: HTTP services (fallback)
  if [ -z "$ip" ]; then
    ip=$(curl -s --max-time 10 https://checkip.amazonaws.com/)
  fi
  
  # Tier 3: Alternative HTTP services
  if [ -z "$ip" ]; then
    ip=$(curl -s --max-time 10 https://ipv4.icanhazip.com/)
  fi
  
  # Validation: Filter private IP ranges
  if echo "$ip" | grep -E "^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)" >/dev/null; then
    return 1  # Private IP detected
  fi
  
  echo "$ip"
}

```

### Provider Abstraction Pattern  
```bash
# Educational example: Provider abstraction pattern
update_dns() {
  provider="$1"
  domain="$2"
  ip="$3"
  
  # Load provider-specific module
  . "providers/${provider}.sh"
  
  # Call standardized interface
  provider_update_record "$domain" "$ip"
}

```

### Dynamic Module Loading Pattern
```bash
# Educational example: Dynamic module loading
load_providers() {
  for provider_file in providers/*.sh; do
    if [ -f "$provider_file" ]; then
      provider_name=$(basename "$provider_file" .sh)
      . "$provider_file"
      echo "✅ Loaded provider: $provider_name"
    fi
  done
}

```

## 🌐 Supported Providers (Learn Different Integration Patterns)

### Cloud Providers (Enterprise Patterns)

#### AWS Route53
- **Description**: Enterprise DNS with global infrastructure
- **Technical Requirement**: AWS CLI (aws route53 commands)
- **Integration Pattern**: JSON API calls via AWS CLI
- **Educational Value**: See how to integrate with enterprise cloud APIs


#### Google Cloud DNS
- **Description**: Google's global DNS infrastructure
- **Technical Requirement**: gcloud CLI (gcloud dns commands)
- **Integration Pattern**: YAML configuration via gcloud
- **Educational Value**: Learn different CLI integration patterns


#### Azure DNS
- **Description**: Microsoft's cloud DNS service
- **Technical Requirement**: Azure CLI (az network dns commands)
- **Integration Pattern**: Azure resource management
- **Educational Value**: Understand Azure resource model through DNS



### Traditional Providers (API Integration Patterns)

#### Cloudflare
- **Description**: Leading CDN and DNS provider with developer-friendly API
- **Technical Requirement**: API credentials
- **Integration Pattern**: RESTful API with curl
- **Educational Value**: Master RESTful API integration in shell


#### GoDaddy
- **Description**: Popular domain registrar with comprehensive API
- **Technical Requirement**: API key and secret
- **Integration Pattern**: Authenticated REST API calls
- **Educational Value**: Handle API authentication and rate limiting



## 🔐 Security Implementation (Learn Production Security)

### Credential Security Patterns

- **Pattern**: All credentials stored locally in ~/.config/access/config.json
- **Educational Value**: Implement secure local credential storage

- **Pattern**: File permissions set to 600 (user read/write only)
- **Educational Value**: Use Unix permissions for access control

- **Pattern**: No credentials transmitted in URLs or logs
- **Educational Value**: Prevent credential leakage in logs and URLs

- **Pattern**: HTTPS required for all API communication
- **Educational Value**: Enforce secure communication protocols


### Network Security Patterns  

- **Pattern**: Private IP ranges filtered (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- **Educational Value**: Understand and implement RFC 1918 IP filtering

- **Pattern**: DNS queries use secure resolvers (OpenDNS: 208.67.222.222)
- **Educational Value**: Choose and implement secure DNS resolution

- **Pattern**: API rate limiting respected with exponential backoff
- **Educational Value**: Implement proper API rate limiting and retry logic


## 🛠️ Features (With Learning Context)


- **Modular Provider Architecture**: Hot-swappable provider modules in providers/ directory with standardized interfaces - Learn plugin patterns in shell

- **Color-Coded Logging**: Enhanced visual feedback with color-coded status messages and error reporting - Master user-friendly CLI design

- **Dynamic Module Loading**: Runtime loading of provider and utility modules without restart - Understand dynamic system architecture

- **Multi-Provider Support**: Works with major cloud providers and traditional DNS services - Learn API abstraction patterns

- **Automatic IP Detection**: Reliable multi-tier IP detection with DNS and HTTP fallbacks - Build resilient network detection

- **Provider Discovery**: Auto-discover available providers at runtime from modular directory structure - Implement plugin discovery

- **XDG Compliance**: Follows XDG Base Directory specification for configuration - Master proper configuration management

- **Service Integration**: Native systemd service and cron job support - Learn service automation patterns

- **Auto-Update Capability**: Self-updating mechanism for the Access tool itself - Build self-maintaining systems

- **Private IP Filtering**: Automatically filters RFC 1918 private IP ranges - Implement network validation logic

- **Secure Configuration**: Encrypted credential storage with proper file permissions - Master security best practices


## 🚀 Quick Start (Learn by Doing)

### Installation
```bash
# Quick install with curl
curl -sSL https://raw.githubusercontent.com/akaoio/access/main/install.sh | sh

# Manual install (recommended for learning)
git clone https://github.com/akaoio/access.git
cd access
./install.sh
```

### Educational Usage Flow
```bash
# 1. Learn IP detection
access ip --debug

# 2. Explore available providers
access providers

# 3. Configure your first provider (start with Cloudflare for learning)
access config cloudflare --email=your@email.com --api-key=your_key

# 4. Test DNS update (dry run first)
ACCESS_DRY_RUN=true access update

# 5. Real update
access update

# 6. Set up continuous monitoring
access daemon
```

## 📚 Learning Outcomes

### 

- Write portable POSIX shell scripts that work everywhere

- Implement complex logic without external dependencies

- Handle errors gracefully with proper exit codes

- Create modular, maintainable shell architectures


### Design eternal infrastructure that outlasts technology trends,Implement plugin architectures in shell,Create resilient systems with multiple fallback strategies,Abstract different APIs behind unified interfaces

- Design eternal infrastructure that outlasts technology trends

- Implement plugin architectures in shell

- Create resilient systems with multiple fallback strategies

- Abstract different APIs behind unified interfaces


### Integrate with RESTful APIs using curl,Implement secure credential management,Handle DNS operations programmatically,Build network-resilient applications

- Integrate with RESTful APIs using curl

- Implement secure credential management

- Handle DNS operations programmatically

- Build network-resilient applications


### Create self-updating systems with rollback capability,Implement proper logging and monitoring,Build systemd services and cron jobs,Design XDG-compliant configuration systems

- Create self-updating systems with rollback capability

- Implement proper logging and monitoring

- Build systemd services and cron jobs

- Design XDG-compliant configuration systems


## 💼 Why This Matters for Your Career

### Why Access is the Perfect Learning Platform

Access demonstrates how to build production-grade infrastructure using only fundamental Unix tools. It's a masterclass in systems programming that teaches eternal skills.

**One tool. Maximum education. Applicable forever.**

#### Career Benefits:

- Shell skills work on every Unix system - from embedded devices to supercomputers

- Understanding DNS is fundamental to all network programming

- Learning to build without dependencies creates truly portable solutions

- Mastering Unix philosophy improves all your system design

- These patterns apply to any infrastructure programming challenge


## 🔧 Commands (Educational Context)



## 🧪 Development & Testing

Access follows strict POSIX compliance for maximum compatibility and eternal reliability.

### Requirements for Learning
- POSIX-compliant shell (sh, bash, dash, ash)
- Standard utilities: curl/wget, dig/nslookup, cron
- Provider-specific CLIs (optional, for advanced learning)

### Educational Testing Approach
```bash
# Run all tests (learn test patterns)
./tests/run-all.sh

# Test specific provider (focused learning)
./tests/test-cloudflare.sh

# Test in different shells (compatibility learning)
dash ./tests/run-all.sh
ash ./tests/run-all.sh
```

## 📊 Environment Variables (Configuration Patterns)

| Variable | Description | Default | Educational Note |
|----------|-------------|---------|------------------|

| `ACCESS_PROVIDER` | DNS provider to use | `` | Learn configuration patterns |

| `ACCESS_DOMAIN` | Domain to update | `` | Learn configuration patterns |

| `ACCESS_HOST` | Host record (@ for root) | `@` | Learn configuration patterns |

| `ACCESS_INTERVAL` | Update interval in seconds | `300` | Learn configuration patterns |

| `AUTO_UPDATE` | Enable auto-updates | `false` | Learn configuration patterns |

| `ACCESS_DRY_RUN` | Test mode without making changes | `false` | Learn configuration patterns |


## 🆘 Support & Community Learning

- **Issues**: [GitHub Issues](https://github.com/akaoio/access/issues) - Learn from real problems
- **Documentation**: [GitHub Wiki](https://github.com/akaoio/access/wiki) - Deep technical guides
- **Source Code**: Study the implementation patterns in `src/`

## 🎯 Next Steps in Your Learning Journey

1. **Master the Basics**: Start with `access ip` and understand IP detection
2. **Provider Integration**: Configure and test different DNS providers
3. **Advanced Patterns**: Study the modular architecture in `providers/`
4. **Shell Mastery**: Analyze the POSIX compliance patterns
5. **Create Your Own**: Build a custom provider using Access patterns

---

* - *

*Pure POSIX shell for eternal reliability - A masterclass in systems programming*

**🎓 Learn. Build. Master. Forever.**