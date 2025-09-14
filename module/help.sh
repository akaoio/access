#!/bin/sh
# Help module for Access Eternal

show_help() {
    printf "Access Eternal - Minimal POSIX dynamic DNS\n"
    printf "\n"
    printf "Usage: access <command>\n"
    printf "\n"
    printf "Commands:\n"
    printf "  ip        Show current IPv4 and IPv6 addresses\n"
    printf "  sync      Synchronize DNS records with current IP\n"
    printf "  status    Show system status and monitoring info\n"
    printf "  update    Update Access to latest version\n"
    printf "  uninstall Remove Access from system\n"
    printf "  help      Show this help message\n"
}

main() {
    show_help
}