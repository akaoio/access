#!/bin/sh
# IP module for Access Eternal

get_ipv4() {
    result=$(ip -4 addr show | grep "scope global" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$result" ]; then
        printf "%s" "$result"
    else
        printf "Not available"
    fi
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