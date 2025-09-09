#!/bin/sh
# IP module for Access Eternal

get_ipv4() {
    ip -4 addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "Not available"
}

get_ipv6() {
    ip -6 addr show | grep 'inet6 ' | grep -v '::1' | grep 'scope global' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "Not available"
}

show_ip() {
    echo "IPv4: $(get_ipv4)"
    echo "IPv6: $(get_ipv6)"
}

# If called directly, show IP info
if [ "$(basename "$0")" = "ip.sh" ]; then
    show_ip
fi