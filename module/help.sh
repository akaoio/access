#!/bin/sh
# Help module for Access Eternal

show_help() {
    echo "Access Eternal - Minimal POSIX dynamic DNS"
    echo ""
    echo "Usage: access <command>"
    echo ""
    echo "Commands:"
    echo "  ip    Show current IPv4 and IPv6 addresses"
    echo "  help  Show this help message"
}

# If called directly, show help
if [ "$(basename "$0")" = "help.sh" ]; then
    show_help
fi