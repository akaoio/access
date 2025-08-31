# Access Installation Guide

## Interactive Installation (Recommended)

For the best installation experience, use the interactive wizard:

```bash
./interactive-install.sh
```

### Features of Interactive Installation

- **Environment Analysis**: Automatically detects your system capabilities
- **Expert Recommendations**: Provides personalized suggestions based on your setup
- **Complete Control**: All features are optional - nothing is forced
- **Clear Explanations**: Detailed information about each option
- **User-Friendly**: Guides you through every decision

## Scan/Peer Discovery Feature

### Important: Completely Optional

The scan/peer discovery feature is **completely optional** and designed for advanced multi-system deployments. Access works perfectly for basic dynamic DNS without this feature.

### When to Enable Scan Feature

**✅ Consider Enabling If You Have:**
- Multiple servers/systems running Access
- Need for automatic load balancing across IP addresses
- Complex network topologies requiring peer coordination
- Advanced infrastructure with multiple geographic locations

**❌ Keep Disabled If You Have:**
- Single system/server setup
- Basic home dynamic DNS needs
- Simple network configuration  
- Want minimal complexity

### Expert Recommendations

The interactive installer analyzes your environment and provides recommendations:

- **Advanced users + Complex networks**: Scan feature recommended
- **Intermediate users + Moderate networks**: Scan feature optional
- **Beginner users + Simple networks**: Scan feature not recommended

## Installation Options

### 1. Interactive Wizard (Recommended)
```bash
./interactive-install.sh
```
- Full guided experience
- Expert recommendations
- Environment analysis
- Complete user control

### 2. Quick Installation
```bash
./install.sh
```
- Redundant automation (systemd + cron)
- Interactive prompts for key decisions
- Scan feature disabled by default

### 3. Non-Interactive Installation
```bash
./install.sh --non-interactive
```
- Uses defaults for automated deployment
- Scan feature disabled by default
- Suitable for CI/CD pipelines

### 4. Command Line Options
```bash
# Specific automation methods
./install.sh --service-only        # Systemd service only
./install.sh --cron-only          # Cron job only
./install.sh --manual-only        # Manual execution

# Optional features
./install.sh --scan               # Enable scan feature
./install.sh --auto-update        # Enable auto-updates
./install.sh --interval=10        # Custom update interval
```

## Configuration Management

### After Installation

Use the configuration wizard for easy management:

```bash
./access-wizard                   # Interactive configuration menu
```

### Scan Feature Management

```bash
# Enable/disable scan feature
./access-wizard scan enable       # Enable scan feature
./access-wizard scan disable      # Disable scan feature
./access-wizard scan toggle       # Toggle scan on/off

# Configure scan settings
./access-wizard scan setup        # Interactive scan configuration
```

### Other Configuration Options

```bash
./access-wizard reconfigure       # Change specific settings
./access-wizard automation        # Change automation method
./access-wizard interval          # Change update interval
./access-wizard status            # Show current configuration
```

## Configuration Files

### Main Configuration
- `~/.config/access/config.json` - Main Access configuration
- `~/.config/access/wizard.json` - Installation wizard preferences

### Scan Configuration (Optional)
- `~/.config/access/scan.json` - Scan feature configuration (only if enabled)

### Data and Logs
- `~/.local/share/access/` - Data files and logs
- `~/.local/state/access/` - State files

## Uninstalling

To completely remove Access:

```bash
./uninstall.sh
```

This removes:
- All installed files
- Configuration directories
- Service files (systemd/cron)
- Log files

## Troubleshooting

### Scan Feature Issues

If you enabled the scan feature and encounter problems:

1. **Disable scan feature temporarily**:
   ```bash
   ./access-wizard scan disable
   ```

2. **Check scan configuration**:
   ```bash
   cat ~/.config/access/scan.json
   ```

3. **Reconfigure scan settings**:
   ```bash
   ./access-wizard scan setup
   ```

### General Issues

1. **Check Access status**:
   ```bash
   access status
   ```

2. **View configuration**:
   ```bash
   ./access-wizard status
   ```

3. **Reconfigure if needed**:
   ```bash
   ./access-wizard reconfigure
   ```

## Best Practices

### For Single-System Users
- Use default installation (scan disabled)
- Enable redundant automation for reliability
- Consider auto-updates for security

### For Multi-System Users
- Consider enabling scan feature after understanding its purpose
- Test scan functionality in development first
- Use consistent configuration across systems

### For Advanced Users
- Review all options in interactive installer
- Customize intervals based on your network dynamics
- Monitor scan logs if using peer discovery

## Security Considerations

- Configuration files are created with secure permissions (600)
- API credentials are stored locally only
- Scan feature requires DNS provider API access
- Regular updates recommended for security patches

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review configuration with `./access-wizard status`
3. Test with basic functionality before enabling advanced features
4. Consider disabling scan feature if experiencing issues