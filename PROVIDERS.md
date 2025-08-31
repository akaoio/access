# DNS Providers - 

Complete guide to supported DNS providers and their configuration.

## Overview

 supports multiple DNS providers for automatic IP synchronization. Each provider is implemented as a pure POSIX shell module with standardized interfaces.

## Supported Providers



## Provider Comparison

| Provider | Setup Difficulty | Rate Limits | IPv6 Support | DNSSEC | Cost |
|----------|------------------|-------------|--------------|--------|------|


## Adding New Providers

To add support for a new DNS provider:

### 1. Create Provider Module

Create `providers/your-provider.sh`:

```bash
#!/bin/sh
# Your Provider DNS synchronization module

provider_name="Your Provider"
provider_id="your-provider"

# Required: Sync DNS records
provider_sync() {
    # Implementation here
    return 0
}

# Required: Validate configuration
provider_validate() {
    # Check required config
    return 0
}

# Required: Interactive configuration
provider_configure() {
    # Setup wizard
    return 0
}

# Optional: Health check
provider_health() {
    # Check connectivity
    return 0
}
```

### 2. Implement Required Functions

All providers must implement:
- `provider_sync()` - Synchronize DNS records
- `provider_validate()` - Validate configuration
- `provider_configure()` - Interactive setup

### 3. Add Configuration Schema

Define required configuration keys:

```bash
provider_config_keys="
    provider.your-provider.api_key
    provider.your-provider.api_secret
    provider.your-provider.zone_id
"
```

### 4. Add Tests

Create `tests/test-your-provider.sh`:

```bash
#!/bin/sh
# Test suite for your provider

test_your_provider_sync() {
    # Test sync functionality
}

test_your_provider_validate() {
    # Test validation
}
```

### 5. Update Documentation

Add provider documentation to YAML atoms in `src/doc/`.

### 6. Submit Pull Request

Ensure all tests pass and documentation is complete.

## Troubleshooting

### Common Issues

#### Authentication Errors
```
Error: Authentication failed for provider
```

**Solution**: Verify API credentials are correct and have required permissions.

#### Rate Limit Exceeded
```
Error: Rate limit exceeded, retry after 300 seconds
```

**Solution**: Access automatically implements exponential backoff. Wait for the retry period.

#### DNS Propagation Delays
```
Warning: DNS record not yet propagated
```

**Solution**: DNS changes can take time to propagate. This is normal behavior.

### Debug Mode

Enable debug logging:

```bash
export ACCESS_DEBUG=1
access sync
```

### Log Analysis

View detailed logs:

```bash
access logs --provider your-provider --level debug
```

## Best Practices

### Security
- Store API credentials securely
- Use least-privilege API keys
- Enable API key rotation
- Monitor for unauthorized access

### Performance
- Configure appropriate sync intervals
- Use multiple providers for redundancy
- Monitor API usage against rate limits
- Cache DNS lookups when possible

### Monitoring
- Set up health checks
- Monitor sync success rates
- Track API response times
- Alert on configuration changes

---

*Generated with ❤️ by @akaoio/composer*