#!/bin/sh
# SSL/TLS certificate management - Pure shell implementation
# Production-ready Let's Encrypt with automatic DNS challenge

set -e

# Configuration
SSL_HOME="${SSL_HOME:-$HOME/.access/ssl}"
LETSENCRYPT_HOME="${LETSENCRYPT_HOME:-/etc/letsencrypt}"
ACME_HOME="${ACME_HOME:-$HOME/.acme.sh}"
PRODUCTION_MODE="${PRODUCTION_MODE:-true}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSL: $*"
}

# Check for required tools
check_requirements() {
    local missing=""
    
    # Check for OpenSSL (required)
    if ! command -v openssl >/dev/null 2>&1; then
        missing="$missing openssl"
    fi
    
    # Check for curl (required for acme.sh)
    if ! command -v curl >/dev/null 2>&1; then
        missing="$missing curl"
    fi
    
    if [ -n "$missing" ]; then
        log "Error: Required tools missing:$missing"
        exit 1
    fi
}

# Install acme.sh if not present
install_acme() {
    if [ ! -f "$ACME_HOME/acme.sh" ]; then
        log "Installing acme.sh for Let's Encrypt support..."
        curl -s https://get.acme.sh | sh -s email=$1
        
        if [ -f "$ACME_HOME/acme.sh" ]; then
            log "✓ acme.sh installed successfully"
            # Set default CA to Let's Encrypt
            "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt
        else
            log "✗ Failed to install acme.sh"
            return 1
        fi
    fi
    return 0
}

# Generate self-signed certificate
generate_self_signed() {
    local domain="${1:-localhost}"
    local key_path="$SSL_HOME/self-signed/key.pem"
    local cert_path="$SSL_HOME/self-signed/cert.pem"
    
    log "Generating self-signed certificate for $domain..."
    
    # Create SSL directory
    mkdir -p "$SSL_HOME/self-signed"
    
    # Generate private key and certificate
    openssl req -x509 \
        -newkey rsa:2048 \
        -keyout "$key_path" \
        -out "$cert_path" \
        -days "$SELF_SIGNED_DAYS" \
        -nodes \
        -subj "/CN=$domain" \
        -addext "subjectAltName=DNS:$domain,DNS:*.$domain,IP:127.0.0.1" 2>/dev/null || \
    openssl req -x509 \
        -newkey rsa:2048 \
        -keyout "$key_path" \
        -out "$cert_path" \
        -days "$SELF_SIGNED_DAYS" \
        -nodes \
        -subj "/CN=$domain"
    
    if [ -f "$key_path" ] && [ -f "$cert_path" ]; then
        log "✓ Self-signed certificate generated"
        log "  Key:  $key_path"
        log "  Cert: $cert_path"
        
        # Set secure permissions
        chmod 600 "$key_path"
        chmod 644 "$cert_path"
        
        return 0
    else
        log "✗ Failed to generate self-signed certificate"
        return 1
    fi
}

# Setup Let's Encrypt with HTTP challenge
setup_letsencrypt_http() {
    local domain="$1"
    local email="$2"
    local webroot="${3:-/var/www/html}"
    
    log "Setting up Let's Encrypt certificate via HTTP challenge..."
    
    # Install acme.sh if needed
    install_acme "$email" || return 1
    
    # Issue certificate with webroot mode
    if "$ACME_HOME/acme.sh" --issue -d "$domain" -w "$webroot" --force; then
        install_certificate "$domain"
        return $?
    fi
    
    return 1
}

# Setup Let's Encrypt with DNS challenge (for wildcard support)
setup_letsencrypt_dns() {
    local domain="$1"
    local email="$2"
    local dns_provider="${3:-godaddy}"
    
    log "Setting up Let's Encrypt certificate via DNS challenge..."
    
    # Install acme.sh if needed
    install_acme "$email" || return 1
    
    # Load DNS credentials from Access config
    local config_file="$HOME/.access/config.json"
    if [ -f "$config_file" ]; then
        if command -v jq >/dev/null 2>&1; then
            local key=$(jq -r '.godaddy.key // ""' "$config_file")
            local secret=$(jq -r '.godaddy.secret // ""' "$config_file")
        else
            # Fallback to grep/sed
            local key=$(grep '"key"' "$config_file" | sed 's/.*"key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            local secret=$(grep '"secret"' "$config_file" | sed 's/.*"secret"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        
        if [ -n "$key" ] && [ -n "$secret" ]; then
            # Export GoDaddy credentials for acme.sh
            export GD_Key="$key"
            export GD_Secret="$secret"
            
            # Issue wildcard certificate
            if "$ACME_HOME/acme.sh" --issue -d "$domain" -d "*.$domain" --dns dns_gd --force; then
                install_certificate "$domain"
                return $?
            fi
        else
            log "Warning: GoDaddy credentials not found in config"
        fi
    fi
    
    return 1
}

# Setup Let's Encrypt with standalone server
setup_letsencrypt_standalone() {
    local domain="$1"
    local email="$2"
    local port="${3:-80}"
    
    log "Setting up Let's Encrypt certificate via standalone server..."
    
    # Install acme.sh if needed
    install_acme "$email" || return 1
    
    # Check if port 80 is available
    if netstat -tln 2>/dev/null | grep -q ":$port "; then
        log "Warning: Port $port is in use. Trying alternate port 8080..."
        port=8080
    fi
    
    # Issue certificate with standalone mode
    if "$ACME_HOME/acme.sh" --issue -d "$domain" --standalone --httpport "$port" --force; then
        install_certificate "$domain"
        return $?
    fi
    
    return 1
}

# Install certificate from acme.sh to Access SSL directory
install_certificate() {
    local domain="$1"
    local acme_cert="$ACME_HOME/$domain/fullchain.cer"
    local acme_key="$ACME_HOME/$domain/$domain.key"
    
    if [ -f "$acme_cert" ] && [ -f "$acme_key" ]; then
        mkdir -p "$SSL_HOME/production"
        
        # Install certificate
        "$ACME_HOME/acme.sh" --install-cert -d "$domain" \
            --key-file "$SSL_HOME/production/key.pem" \
            --fullchain-file "$SSL_HOME/production/cert.pem" \
            --reloadcmd "echo 'Certificate installed'"
        
        if [ -f "$SSL_HOME/production/cert.pem" ]; then
            log "✓ Production certificate installed"
            log "  Key:  $SSL_HOME/production/key.pem"
            log "  Cert: $SSL_HOME/production/cert.pem"
            
            # Set secure permissions
            chmod 600 "$SSL_HOME/production/key.pem"
            chmod 644 "$SSL_HOME/production/cert.pem"
            
            return 0
        fi
    fi
    
    log "✗ Failed to install certificate"
    return 1
}

# Smart Let's Encrypt setup with fallback chain
setup_letsencrypt() {
    local domain="$1"
    local email="${2:-admin@$domain}"
    
    log "Starting production SSL setup for $domain..."
    
    # Try DNS challenge first (supports wildcards)
    if setup_letsencrypt_dns "$domain" "$email"; then
        log "✓ SSL setup successful via DNS challenge"
        return 0
    fi
    
    # Try standalone server
    if setup_letsencrypt_standalone "$domain" "$email"; then
        log "✓ SSL setup successful via standalone server"
        return 0
    fi
    
    # Try HTTP webroot as last resort
    if setup_letsencrypt_http "$domain" "$email"; then
        log "✓ SSL setup successful via HTTP challenge"
        return 0
    fi
    
    log "✗ All Let's Encrypt methods failed"
    
    # In production mode, don't fall back to self-signed
    if [ "$PRODUCTION_MODE" = "true" ]; then
        log "ERROR: Production mode requires valid certificates"
        log "Please ensure:"
        log "  1. Domain $domain points to this server"
        log "  2. Ports 80/443 are accessible"
        log "  3. DNS credentials are configured for wildcard certificates"
        return 1
    else
        log "Development mode: Generating self-signed certificate..."
        generate_self_signed "$domain"
    fi
}

# Renew Let's Encrypt certificate
renew_letsencrypt() {
    log "Renewing Let's Encrypt certificates..."
    
    # Use acme.sh for renewal
    if [ -f "$ACME_HOME/acme.sh" ]; then
        if "$ACME_HOME/acme.sh" --renew-all --force; then
            log "✓ Certificates renewed successfully"
            return 0
        fi
    fi
    
    # Fallback to certbot if available
    if command -v certbot >/dev/null 2>&1; then
        local sudo_cmd=""
        if [ ! -w "$LETSENCRYPT_HOME" ] && [ "$(id -u)" -ne 0 ]; then
            sudo_cmd="sudo"
        fi
        
        if $sudo_cmd certbot renew --quiet; then
            log "✓ Certificates renewed via certbot"
            return 0
        fi
    fi
    
    log "✗ Certificate renewal failed"
    return 1
}

# Check certificate status
check_certificate() {
    local cert_path="$1"
    
    if [ ! -f "$cert_path" ]; then
        log "Certificate not found: $cert_path"
        return 1
    fi
    
    # Get certificate details
    local subject=$(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null)
    local issuer=$(openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null)
    local dates=$(openssl x509 -in "$cert_path" -noout -dates 2>/dev/null)
    
    # Check if certificate is valid
    if openssl x509 -in "$cert_path" -noout -checkend 0 >/dev/null 2>&1; then
        log "✓ Certificate is valid"
    else
        log "✗ Certificate has expired or is invalid"
        return 1
    fi
    
    # Extract expiry date
    local not_after=$(echo "$dates" | grep "notAfter" | cut -d= -f2)
    
    # Check if expiring soon (within 30 days)
    if openssl x509 -in "$cert_path" -noout -checkend 2592000 >/dev/null 2>&1; then
        log "Certificate valid until: $not_after"
    else
        log "⚠ Certificate expiring soon: $not_after"
    fi
    
    # Display certificate details
    echo "$subject"
    echo "$issuer"
    
    return 0
}

# Setup auto-renewal cron job
setup_auto_renewal() {
    local script_path="$(readlink -f "$0")"
    
    log "Setting up auto-renewal cron job..."
    
    # Add to crontab (runs twice daily as recommended by Let's Encrypt)
    (crontab -l 2>/dev/null | grep -v "access.*ssl.*renew"; echo "0 0,12 * * * $script_path renew >/dev/null 2>&1") | crontab -
    
    log "✓ Auto-renewal cron job created (runs twice daily)"
}

# Find best available certificate
find_certificate() {
    local domain="${1:-localhost}"
    
    # Priority order:
    # 1. Production Let's Encrypt certificate (from acme.sh)
    # 2. Let's Encrypt certificate (from certbot)
    # 3. Self-signed certificate (only in dev mode)
    # 4. Error in production mode
    
    # Check production certificate from acme.sh
    if [ -f "$SSL_HOME/production/cert.pem" ]; then
        if check_certificate "$SSL_HOME/production/cert.pem" >/dev/null 2>&1; then
            echo "$SSL_HOME/production/key.pem:$SSL_HOME/production/cert.pem"
            return 0
        fi
    fi
    
    # Check Let's Encrypt from certbot
    if [ -f "$SSL_HOME/letsencrypt/cert.pem" ]; then
        if check_certificate "$SSL_HOME/letsencrypt/cert.pem" >/dev/null 2>&1; then
            echo "$SSL_HOME/letsencrypt/key.pem:$SSL_HOME/letsencrypt/cert.pem"
            return 0
        fi
    fi
    
    # In production mode, we require valid certificates
    if [ "$PRODUCTION_MODE" = "true" ]; then
        log "ERROR: No valid production certificate found"
        log "Run: access ssl letsencrypt $domain"
        return 1
    fi
    
    # Development mode only: use or generate self-signed
    if [ -f "$SSL_HOME/self-signed/cert.pem" ]; then
        if check_certificate "$SSL_HOME/self-signed/cert.pem" >/dev/null 2>&1; then
            echo "$SSL_HOME/self-signed/key.pem:$SSL_HOME/self-signed/cert.pem"
            return 0
        fi
    fi
    
    # Generate new self-signed (dev mode only)
    if generate_self_signed "$domain"; then
        echo "$SSL_HOME/self-signed/key.pem:$SSL_HOME/self-signed/cert.pem"
        return 0
    fi
    
    return 1
}

# Main command handler
case "${1:-help}" in
    generate)
        check_requirements
        domain="${2:-localhost}"
        generate_self_signed "$domain"
        ;;
        
    letsencrypt)
        check_requirements
        domain="$2"
        email="$3"
        webroot="${4:-/var/www/html}"
        
        if [ -z "$domain" ]; then
            log "Error: Domain required for Let's Encrypt"
            log "Usage: $0 letsencrypt <domain> [email] [webroot]"
            exit 1
        fi
        
        setup_letsencrypt "$domain" "$email" "$webroot"
        ;;
        
    renew)
        check_requirements
        renew_letsencrypt
        ;;
        
    check)
        cert_path="${2:-$SSL_HOME/letsencrypt/cert.pem}"
        if [ ! -f "$cert_path" ]; then
            cert_path="$SSL_HOME/self-signed/cert.pem"
        fi
        check_certificate "$cert_path"
        ;;
        
    auto-renew)
        setup_auto_renewal
        ;;
        
    find)
        domain="${2:-localhost}"
        result=$(find_certificate "$domain")
        if [ $? -eq 0 ]; then
            key_path=$(echo "$result" | cut -d: -f1)
            cert_path=$(echo "$result" | cut -d: -f2)
            echo "Key:  $key_path"
            echo "Cert: $cert_path"
        else
            log "No valid certificate found"
            exit 1
        fi
        ;;
        
    production)
        shift
        export PRODUCTION_MODE="true"
        case "${1:-help}" in
            setup)
                domain="$2"
                email="${3:-admin@$domain}"
                if [ -z "$domain" ]; then
                    log "Error: Domain required"
                    exit 1
                fi
                setup_letsencrypt "$domain" "$email"
                ;;
            *)
                log "Production mode enabled - self-signed certificates disabled"
                "$0" "$@"
                ;;
        esac
        ;;
        
    *)
        cat <<EOF
Access SSL - Production-ready certificate management

Usage:
    $0 letsencrypt <domain> [email]         Setup Let's Encrypt (auto-detect method)
    $0 production setup <domain> [email]    Production setup (no self-signed fallback)
    $0 renew                                 Renew all certificates
    $0 check [cert_path]                     Check certificate status
    $0 auto-renew                            Setup auto-renewal cron job
    $0 find [domain]                         Find best available certificate
    $0 help                                  Show this help

Development only:
    $0 generate [domain]                    Generate self-signed certificate

Environment variables:
    SSL_HOME              SSL directory (default: ~/.access/ssl)
    PRODUCTION_MODE       Require valid certificates (default: true)
    ACME_HOME            acme.sh directory (default: ~/.acme.sh)

Certificate Methods (tried in order):
    1. DNS Challenge     - Wildcard support, uses GoDaddy API from Access config
    2. Standalone Server - Temporary web server on port 80/8080
    3. HTTP Challenge    - Requires existing web server with webroot

Examples:
    # Production setup with wildcard certificate
    $0 production setup example.com admin@example.com
    
    # Standard setup (tries all methods)
    $0 letsencrypt example.com
    
    # Setup auto-renewal
    $0 auto-renew
    
    # Check certificate status
    $0 check

Notes:
    - Production mode enforces valid certificates (no self-signed)
    - DNS challenge automatically uses GoDaddy credentials from Access config
    - Wildcard certificates (*.$domain) are included with DNS challenge
    - acme.sh is automatically installed if not present

EOF
        ;;
esac