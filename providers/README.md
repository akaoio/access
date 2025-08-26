# DNS Provider Interface

Each provider must implement the following functions:

## Required Functions

### `provider_info()`
Returns provider metadata.
```sh
provider_info() {
    echo "name: Provider Name"
    echo "version: 1.0.0"
    echo "author: Author Name"
    echo "type: dns|blockchain|crypto|custom"
}
```

### `provider_config()`
Returns required configuration fields.
```sh
provider_config() {
    echo "field: key, type: string, required: true, description: API Key"
    echo "field: secret, type: string, required: true, description: API Secret"
}
```

### `provider_validate()`
Validates configuration before use.
```sh
provider_validate() {
    # Return 0 if valid, 1 if invalid
}
```

### `provider_update()`
Updates DNS record with new IP.
```sh
provider_update() {
    local domain="$1"
    local host="$2"
    local ip="$3"
    # Additional args passed via environment
    # Return 0 on success, 1 on failure
}
```

## Optional Functions

### `provider_test()`
Tests provider connectivity.

### `provider_cleanup()`
Cleanup resources if needed.

## Environment Variables

Providers receive configuration via environment variables prefixed with provider name:
- `GODADDY_KEY`
- `GODADDY_SECRET`
- `CLOUDFLARE_EMAIL`
- etc.

## Provider Types

- **dns**: Traditional DNS providers (GoDaddy, Cloudflare)
- **blockchain**: Blockchain-based domains (ENS, Unstoppable)
- **crypto**: Cryptocurrency domains (Handshake, Namecoin)
- **custom**: Custom implementations