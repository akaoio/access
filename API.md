# API Documentation - 

This document describes the internal API and function interfaces for .

## Core API Functions



## Provider Interface

All DNS providers must implement the following interface:

### Required Functions

#### `provider_sync()`
Synchronize DNS records with the provider.

**Returns**: 0 on success, non-zero on failure

#### `provider_validate()`
Validate provider configuration.

**Returns**: 0 if valid, non-zero if invalid

#### `provider_configure()`
Interactive configuration setup.

**Returns**: 0 on success, non-zero on failure

### Optional Functions

#### `provider_health()`
Check provider connectivity and health.

**Returns**: 0 if healthy, non-zero if unhealthy

#### `provider_status()`
Get current provider status information.

**Returns**: Status information

## Configuration API

### `config_get(key)`
Retrieve configuration value.

**Parameters**:
- `key` (string): Configuration key in dot notation

**Returns**: Configuration value or empty string

**Example**:
```bash
api_key=$(config_get "provider.cloudflare.api_key")
```

### `config_set(key, value)`
Set configuration value.

**Parameters**:
- `key` (string): Configuration key in dot notation
- `value` (string): Value to set

**Returns**: 0 on success, non-zero on failure

### `config_delete(key)`
Delete configuration key.

**Parameters**:
- `key` (string): Configuration key to delete

**Returns**: 0 on success, non-zero on failure

## Utility Functions

### `log_info(message)`
Log informational message.

### `log_error(message)`
Log error message.

### `log_debug(message)`
Log debug message (only when debug mode enabled).

### `is_valid_ip(ip)`
Validate IP address format.

**Returns**: 0 if valid, 1 if invalid

### `get_current_ip()`
Get current public IP address.

**Returns**: Current IP address

### `dns_lookup(hostname)`
Perform DNS lookup for hostname.

**Returns**: Resolved IP address

## Error Codes

| Code | Description |
|------|-------------|
| 0    | Success |
| 1    | General error |
| 2    | Configuration error |
| 3    | Network error |
| 4    | Authentication error |
| 5    | Permission error |
| 6    | Provider error |
| 7    | Validation error |

## Environment Variables



---

*Generated with ❤️ by @akaoio/composer*