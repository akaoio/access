#!/bin/sh
# IP module for Access Eternal

get_ipv4() {
    # Try to get public IPv4 from external services
    public_ipv4=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || curl -s -4 --max-time 5 icanhazip.com 2>/dev/null)
    if [ -n "$public_ipv4" ] && [ "$public_ipv4" != "Not available" ]; then
        printf "%s" "$public_ipv4"
        return
    fi
    
    # If public IP detection fails, return "Not available" instead of falling back to local IP
    printf "Not available"
}

get_ipv6() {
    # Prefer stable IPv6 over temporary privacy addresses
    stable_ipv6=$(ip -6 addr show | grep "scope global" | grep -v "temporary" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$stable_ipv6" ]; then
        printf "%s" "$stable_ipv6"
        return
    fi
    
    # Fallback to any global IPv6 (including temporary)
    temp_ipv6=$(ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$temp_ipv6" ]; then
        printf "%s" "$temp_ipv6"
        return
    fi
    
    printf "Not available"
}

get_ip() {
    # Legacy function - prioritize stable IPv6 over temporary, then IPv4
    stable_ipv6=$(ip -6 addr show | grep "scope global" | grep -v "temporary" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$stable_ipv6" ]; then
        printf "%s" "$stable_ipv6"
        return
    fi
    
    # Fallback to any global IPv6
    temp_ipv6=$(ip -6 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$temp_ipv6" ]; then
        printf "%s" "$temp_ipv6"
        return
    fi
    
    # Fallback to IPv4
    ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1
}

main() {
    printf "IPv4: %s\n" "$(get_ipv4)"
    printf "IPv6: %s\n" "$(get_ipv6)"
}