#!/bin/sh
# SSL/TLS certificate management - Pure shell implementation
# Provides both self-signed and Let's Encrypt certificates

set -e

# Configuration
SSL_HOME="${SSL_HOME:-$HOME/.access/ssl}"
LETSENCRYPT_HOME="${LETSENCRYPT_HOME:-/etc/letsencrypt}"
SELF_SIGNED_DAYS="${SELF_SIGNED_DAYS:-365}"

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
    
    # Check for certbot (optional, for Let's Encrypt)
    if ! command -v certbot >/dev/null 2>&1; then
        log "Warning: certbot not found. Let's Encrypt support disabled."
        log "Install with: sudo apt-get install certbot (Debian/Ubuntu)"
        log "           or: sudo yum install certbot (RHEL/CentOS)"
    fi
    
    if [ -n "$missing" ]; then
        log "Error: Required tools missing:$missing"
        exit 1
    fi
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

# Setup Let's Encrypt certificate
setup_letsencrypt() {
    local domain="$1"
    local email="$2"
    local webroot="${3:-/var/www/html}"
    
    if ! command -v certbot >/dev/null 2>&1; then
        log "Error: certbot not installed. Cannot use Let's Encrypt."
        log "Falling back to self-signed certificate..."
        generate_self_signed "$domain"
        return 1
    fi
    
    log "Setting up Let's Encrypt certificate for $domain..."
    
    # Check if we need sudo
    local sudo_cmd=""
    if [ ! -w "$LETSENCRYPT_HOME" ] && [ "$(id -u)" -ne 0 ]; then
        sudo_cmd="sudo"
    fi
    
    # Certbot command options
    local certbot_opts="certonly --webroot"
    certbot_opts="$certbot_opts --webroot-path $webroot"
    certbot_opts="$certbot_opts --domain $domain"
    certbot_opts="$certbot_opts --non-interactive"
    certbot_opts="$certbot_opts --agree-tos"
    
    if [ -n "$email" ]; then
        certbot_opts="$certbot_opts --email $email"
    else
        certbot_opts="$certbot_opts --register-unsafely-without-email"
    fi
    
    # Try to obtain certificate
    if $sudo_cmd certbot $certbot_opts; then
        local key_path="$LETSENCRYPT_HOME/live/$domain/privkey.pem"
        local cert_path="$LETSENCRYPT_HOME/live/$domain/fullchain.pem"
        
        if [ -f "$key_path" ] && [ -f "$cert_path" ]; then
            log "✓ Let's Encrypt certificate obtained"
            log "  Key:  $key_path"
            log "  Cert: $cert_path"
            
            # Create symlinks in Access SSL directory
            mkdir -p "$SSL_HOME/letsencrypt"
            ln -sf "$key_path" "$SSL_HOME/letsencrypt/key.pem"
            ln -sf "$cert_path" "$SSL_HOME/letsencrypt/cert.pem"
            
            return 0
        fi
    fi
    
    log "✗ Failed to obtain Let's Encrypt certificate"
    log "Falling back to self-signed certificate..."
    generate_self_signed "$domain"
    return 1
}

# Renew Let's Encrypt certificate
renew_letsencrypt() {
    if ! command -v certbot >/dev/null 2>&1; then
        log "Error: certbot not installed"
        return 1
    fi
    
    log "Renewing Let's Encrypt certificates..."
    
    # Check if we need sudo
    local sudo_cmd=""
    if [ ! -w "$LETSENCRYPT_HOME" ] && [ "$(id -u)" -ne 0 ]; then
        sudo_cmd="sudo"
    fi
    
    if $sudo_cmd certbot renew --quiet; then
        log "✓ Certificates renewed successfully"
        return 0
    else
        log "✗ Certificate renewal failed"
        return 1
    fi
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
    # 1. Let's Encrypt certificate
    # 2. Self-signed certificate
    # 3. Generate new self-signed
    
    # Check Let's Encrypt
    if [ -f "$SSL_HOME/letsencrypt/cert.pem" ]; then
        if check_certificate "$SSL_HOME/letsencrypt/cert.pem" >/dev/null 2>&1; then
            echo "$SSL_HOME/letsencrypt/key.pem:$SSL_HOME/letsencrypt/cert.pem"
            return 0
        fi
    fi
    
    # Check self-signed
    if [ -f "$SSL_HOME/self-signed/cert.pem" ]; then
        if check_certificate "$SSL_HOME/self-signed/cert.pem" >/dev/null 2>&1; then
            echo "$SSL_HOME/self-signed/key.pem:$SSL_HOME/self-signed/cert.pem"
            return 0
        fi
    fi
    
    # Generate new self-signed
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
        
    *)
        cat <<EOF
Access SSL - Pure shell certificate management

Usage:
    $0 generate [domain]                    Generate self-signed certificate
    $0 letsencrypt <domain> [email] [root]  Setup Let's Encrypt certificate
    $0 renew                                 Renew Let's Encrypt certificates
    $0 check [cert_path]                     Check certificate status
    $0 auto-renew                            Setup auto-renewal cron job
    $0 find [domain]                         Find best available certificate
    $0 help                                  Show this help

Environment variables:
    SSL_HOME              SSL directory (default: ~/.access/ssl)
    LETSENCRYPT_HOME      Let's Encrypt directory (default: /etc/letsencrypt)
    SELF_SIGNED_DAYS      Self-signed validity (default: 365)

Examples:
    # Generate self-signed certificate
    $0 generate example.com
    
    # Setup Let's Encrypt (requires web server)
    $0 letsencrypt example.com admin@example.com /var/www/html
    
    # Setup auto-renewal
    $0 auto-renew
    
    # Find and use best certificate
    $0 find example.com

EOF
        ;;
esac